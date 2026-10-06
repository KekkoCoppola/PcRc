import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_info.dart';
import '../models/command_result.dart';
import '../models/managed_app.dart';
import '../models/pc_status.dart';
import '../models/pending_command.dart';
import '../services/pc_remote.dart';

/// Fase del PC come la vede l'app.
enum PcPhase {
  /// App compilata senza secrets.json: non sa a chi parlare.
  unconfigured,

  /// Prima lettura di Firebase in corso.
  checking,
  off,

  /// Presa accesa, in attesa del primo heartbeat dell'agent.
  booting,
  online,

  /// SHUTDOWN inviato: attesa dello spegnimento di Windows, poi stacco della presa.
  shuttingDown,
}

enum PowerOnResult { started, needsPlugCycle, failed, ignored }

/// Messaggio da mostrare all'utente (snackbar).
class PcMessage {
  const PcMessage(this.text, {this.isError = false});

  final String text;
  final bool isError;
}

/// Stato e comandi del PC: legge Firebase ogni [pollInterval], accende e stacca la presa
/// via Home Assistant, manda START/STOP alle app e SHUTDOWN al PC tramite l'agent.
class PcController extends ChangeNotifier {
  PcController(
    this._remote, {
    this.configured = true,
    this.pollInterval = const Duration(seconds: 3),
    DateTime Function()? now,
    Future<void> Function(Duration)? wait,
  })  : _now = now ?? DateTime.now,
        _wait = wait ?? Future<void>.delayed;

  /// Tempo massimo tra accensione della presa e primo heartbeat (boot + login + agent).
  static const bootTimeout = Duration(minutes: 3);

  /// Tempo massimo tra SHUTDOWN accettato e scomparsa del PC.
  static const shutdownTimeout = Duration(minutes: 3);

  /// Margine tra la scomparsa dell'agent e lo stacco della presa: Windows chiude
  /// l'agent all'inizio dello spegnimento e deve ancora finire di scrivere su disco.
  static const plugOffGrace = Duration(seconds: 60);

  /// Pausa tra spegnimento e riaccensione della presa quando era rimasta accesa.
  static const plugCycleGap = Duration(seconds: 5);

  final PcRemote _remote;
  final bool configured;

  /// Ogni quanto rileggere Firebase; null = solo refresh() manuale (test).
  final Duration? pollInterval;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;

  late PcPhase _phase = configured ? PcPhase.checking : PcPhase.unconfigured;
  PcStatus _pcStatus = const PcStatus();
  Map<String, AppInfo> _apps = {for (final app in managedApps) app.key: AppInfo(key: app.key)};
  CommandResult? _pcResult;
  bool _reachable = true;

  // Comandi alle app: in scrittura su Firebase / in attesa dell'esito dall'agent
  final Set<String> _sending = {};
  final Map<String, PendingCommand> _pending = {};

  bool _plugBusy = false;
  DateTime? _bootStartedAt;

  // Spegnimento: comando in attesa di esito -> scadenza per sparire -> PC sparito da
  PendingCommand? _shutdownCommand;
  DateTime? _shutdownDeadline;
  DateTime? _offlineSince;
  bool _cuttingPlug = false;

  Timer? _timer;
  bool _refreshing = false;
  bool _disposed = false;
  final _messages = StreamController<PcMessage>.broadcast();

  PcPhase get phase => _phase;
  PcStatus get pcStatus => _pcStatus;
  AppInfo app(String key) => _apps[key]!;
  Stream<PcMessage> get messages => _messages.stream;

  /// False se l'ultima lettura di Firebase è fallita.
  bool get reachable => _reachable;

  /// Chiamate a Home Assistant per l'accensione in corso.
  bool get plugBusy => _plugBusy;

  bool isBusy(String appKey) => _pending.containsKey(appKey) || _sending.contains(appKey);

  bool get isPcOnline => _pcStatus.isOnlineAt(_now());

  /// LED del case accesi: c'è corrente e il PC sta partendo o è acceso.
  bool get ledsOn => switch (_phase) {
        PcPhase.booting || PcPhase.online => true,
        PcPhase.shuttingDown => isPcOnline,
        _ => false,
      };

  bool get dashboardVisible => _phase == PcPhase.online || _phase == PcPhase.shuttingDown;

  /// Da quanto si aspetta il PC dopo aver acceso la presa.
  Duration? get bootElapsed =>
      _phase == PcPhase.booting ? _now().difference(_bootStartedAt!) : null;

  /// Avanzamento dello spegnimento, per la card Alimentazione.
  String get shutdownStatus {
    if (_cuttingPlug) return 'Stacco la presa...';
    if (_offlineSince != null) {
      final left = plugOffGrace - _now().difference(_offlineSince!);
      return 'Windows spento, stacco la presa tra ${left.isNegative ? 0 : left.inSeconds}s';
    }
    if (_shutdownDeadline != null) return 'Windows si sta spegnendo...';
    return 'Invio il comando di spegnimento...';
  }

  void start() {
    if (_phase == PcPhase.unconfigured) return;
    refresh();
    final interval = pollInterval;
    if (interval != null) _timer = Timer.periodic(interval, (_) => refresh());
  }

  /// Rilegge Firebase e fa avanzare la fase. Chiamate sovrapposte vengono ignorate.
  Future<void> refresh() async {
    if (_refreshing || _disposed || _phase == PcPhase.unconfigured) return;
    _refreshing = true;
    try {
      final snapshot = await _remote.fetchSnapshot();
      if (_disposed) return;
      _reachable = snapshot != null;
      if (snapshot != null) {
        _pcStatus = snapshot.pcStatus;
        _apps = snapshot.apps;
        _pcResult = snapshot.pcResult;
      }
      _resolveAppCommands();
      await _advancePhase(fetched: snapshot != null);
    } finally {
      _refreshing = false;
    }
    _notify();
  }

  /// Accende la presa del PC. Se è già accesa con il PC spento (es. dopo uno spegnimento
  /// da Windows) ritorna [PowerOnResult.needsPlugCycle]: con [cyclePlug] la spegne e la
  /// riaccende, così il PC riparte.
  Future<PowerOnResult> powerOn({bool cyclePlug = false}) async {
    if (_phase != PcPhase.off || _plugBusy) return PowerOnResult.ignored;
    _plugBusy = true;
    _notify();
    try {
      final plugOn = await _remote.fetchPlugOn();
      if (plugOn == null) {
        _emit('Home Assistant non raggiungibile: presa non comandata.', isError: true);
        return PowerOnResult.failed;
      }
      if (plugOn && !cyclePlug) return PowerOnResult.needsPlugCycle;
      if (plugOn) {
        if (!await _remote.setPlug(false)) {
          _emit('Home Assistant non ha spento la presa.', isError: true);
          return PowerOnResult.failed;
        }
        await _wait(plugCycleGap);
      }
      if (!await _remote.setPlug(true)) {
        _emit('Home Assistant non ha acceso la presa.', isError: true);
        return PowerOnResult.failed;
      }
      _phase = PcPhase.booting;
      _bootStartedAt = _now();
      return PowerOnResult.started;
    } finally {
      _plugBusy = false;
      _notify();
    }
  }

  /// Spegne Windows tramite l'agent; la presa viene staccata quando il PC è spento.
  Future<void> shutdown() async {
    if (_phase != PcPhase.online) return;
    _phase = PcPhase.shuttingDown;
    _shutdownCommand = null;
    _shutdownDeadline = null;
    _offlineSince = null;
    _notify();

    final id = await _remote.sendPcCommand('SHUTDOWN');
    if (_disposed) return;
    if (id == null) {
      _phase = PcPhase.online;
      _emit('Comando di spegnimento non inviato: Firebase non raggiungibile.', isError: true);
    } else {
      _shutdownCommand = PendingCommand(id: id, action: 'SHUTDOWN', sentAt: _now());
      _emit('Spegnimento richiesto: Windows si chiude, poi stacco la presa.');
    }
    _notify();
  }

  /// START se l'app è chiusa, STOP se è aperta. L'esito arriva con i refresh successivi.
  Future<void> toggleApp(String appKey) async {
    if (_phase != PcPhase.online || isBusy(appKey)) return;
    final action = _apps[appKey]!.isRunning ? 'STOP' : 'START';
    _sending.add(appKey);
    _notify();

    final id = await _remote.sendAppCommand(appKey, action);
    if (_disposed) return;
    _sending.remove(appKey);
    final name = managedApp(appKey).displayName;
    if (id == null) {
      _emit('Errore nell\'invio del comando per $name.', isError: true);
    } else {
      _pending[appKey] = PendingCommand(id: id, action: action, sentAt: _now());
      _emit('$name: ${action == 'START' ? 'avvio' : 'chiusura'} richiesto, attendo il PC...');
    }
    _notify();
  }

  Future<void> _advancePhase({required bool fetched}) async {
    final now = _now();
    final online = _pcStatus.isOnlineAt(now);
    switch (_phase) {
      case PcPhase.unconfigured:
        return;
      case PcPhase.checking:
        if (fetched) {
          _phase = online ? PcPhase.online : PcPhase.off;
        } else {
          _phase = PcPhase.off;
          _emit('Firebase non raggiungibile: stato del PC sconosciuto.', isError: true);
        }
      case PcPhase.off:
        if (online) _phase = PcPhase.online;
      case PcPhase.booting:
        if (online) {
          _phase = PcPhase.online;
          _emit('PC acceso e collegato.');
        } else if (now.difference(_bootStartedAt!) > bootTimeout) {
          _phase = PcPhase.off;
          _emit(
            'Il PC non ha risposto entro ${bootTimeout.inMinutes} minuti. '
            'La presa è accesa: controlla il PC.',
            isError: true,
          );
        }
      case PcPhase.online:
        if (fetched && !online) {
          _phase = PcPhase.off;
          _emit('Il PC non risponde più.', isError: true);
        }
      case PcPhase.shuttingDown:
        if (fetched) await _advanceShutdown(now, online);
    }
  }

  Future<void> _advanceShutdown(DateTime now, bool online) async {
    final command = _shutdownCommand;
    if (command == null && _shutdownDeadline == null) return; // comando ancora in scrittura

    if (command != null) {
      switch (command.outcome(_pcResult, now)) {
        case CommandOutcome.waiting:
          // L'agent può sparire prima di pubblicare l'esito: vale come accettato
          if (online) return;
        case CommandOutcome.succeeded:
          break;
        case CommandOutcome.failed:
          _shutdownCommand = null;
          _phase = PcPhase.online;
          _emit('Spegnimento rifiutato: ${_pcResult?.message ?? 'errore sconosciuto'}.',
              isError: true);
          return;
        case CommandOutcome.timedOut:
          _shutdownCommand = null;
          _phase = PcPhase.online;
          _emit('Il PC non ha risposto al comando di spegnimento.', isError: true);
          return;
      }
      _shutdownCommand = null;
      _shutdownDeadline = now.add(shutdownTimeout);
    }

    if (online) {
      _offlineSince = null;
      if (now.isAfter(_shutdownDeadline!)) {
        _shutdownDeadline = null;
        _phase = PcPhase.online;
        _emit('Il PC non si è spento: presa lasciata accesa.', isError: true);
      }
      return;
    }

    _offlineSince ??= now;
    if (now.difference(_offlineSince!) < plugOffGrace) return;

    _cuttingPlug = true;
    _notify();
    final ok = await _remote.setPlug(false);
    _cuttingPlug = false;
    _offlineSince = null;
    _shutdownDeadline = null;
    _phase = PcPhase.off;
    _emit(
      ok ? 'PC spento, presa staccata.' : 'PC spento, ma Home Assistant non ha staccato la presa.',
      isError: !ok,
    );
  }

  /// Chiude i comandi alle app quando l'agent pubblica l'esito (o scade il tempo).
  void _resolveAppCommands() {
    final now = _now();
    for (final key in _pending.keys.toList()) {
      final result = _apps[key]!.result;
      final outcome = _pending[key]!.outcome(result, now);
      if (outcome == CommandOutcome.waiting) continue;

      _pending.remove(key);
      final name = managedApp(key).displayName;
      switch (outcome) {
        case CommandOutcome.succeeded:
          _emit('$name: ${result?.message ?? 'fatto'}.');
        case CommandOutcome.failed:
          _emit('$name: errore, ${result?.message ?? 'sconosciuto'}.', isError: true);
        case CommandOutcome.timedOut:
          _emit('$name: nessuna risposta dal PC.', isError: true);
        case CommandOutcome.waiting:
          break;
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _emit(String text, {bool isError = false}) {
    if (!_disposed) _messages.add(PcMessage(text, isError: isError));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _messages.close();
    _remote.dispose();
    super.dispose();
  }
}
