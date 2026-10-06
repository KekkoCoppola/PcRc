import 'package:flutter_test/flutter_test.dart';
import 'package:pcrc/controllers/pc_controller.dart';
import 'package:pcrc/models/command_result.dart';

import 'support/fake_remote.dart';

void main() {
  late DateTime now;
  late FakeRemote remote;
  late PcController pc;
  late List<PcMessage> messages;

  PcController build({bool configured = true}) {
    final controller = PcController(
      remote,
      configured: configured,
      pollInterval: null,
      now: () => now,
      wait: (duration) async => now = now.add(duration),
    );
    controller.messages.listen(messages.add);
    return controller;
  }

  setUp(() {
    now = DateTime(2026, 10, 7, 9);
    remote = FakeRemote();
    messages = [];
    pc = build();
  });

  tearDown(() => pc.dispose());

  /// Fa passare il tempo (il PC manda heartbeat se [pcAlive]) e rilegge Firebase.
  Future<void> advance(Duration duration, {bool pcAlive = false}) async {
    now = now.add(duration);
    if (pcAlive) remote.heartbeat(now);
    await pc.refresh();
    await Future<void>.delayed(Duration.zero); // consegna dei messaggi
  }

  Future<void> startOnline() async {
    remote.heartbeat(now);
    await pc.refresh();
    expect(pc.phase, PcPhase.online);
  }

  group('stato iniziale', () {
    test('PC with a fresh heartbeat opens straight on the dashboard', () async {
      await startOnline();

      expect(pc.dashboardVisible, isTrue);
      expect(pc.ledsOn, isTrue);
    });

    test('PC silent for an hour is off', () async {
      remote.heartbeat(now.subtract(const Duration(hours: 1)));

      await pc.refresh();

      expect(pc.phase, PcPhase.off);
      expect(pc.ledsOn, isFalse);
    });

    test('Firebase unreachable at start shows off with an error', () async {
      remote.firebaseUp = false;

      await advance(Duration.zero);

      expect(pc.phase, PcPhase.off);
      expect(pc.reachable, isFalse);
      expect(messages.single.isError, isTrue);
    });

    test('build without secrets.json never calls out', () async {
      pc.dispose();
      pc = build(configured: false);

      pc.start();
      await pc.refresh();

      expect(pc.phase, PcPhase.unconfigured);
      expect(await pc.powerOn(), PowerOnResult.ignored);
      expect(remote.calls, isEmpty);
    });
  });

  group('accensione', () {
    setUp(() async => pc.refresh()); // PC spento: nessun heartbeat

    test('plug off: turns it on and waits for the first heartbeat', () async {
      expect(await pc.powerOn(), PowerOnResult.started);

      expect(remote.calls, ['plug?', 'plug:on']);
      expect(pc.phase, PcPhase.booting);
      expect(pc.ledsOn, isTrue);

      await advance(const Duration(seconds: 40), pcAlive: true);

      expect(pc.phase, PcPhase.online);
      expect(messages.last.isError, isFalse);
    });

    test('plug already on (PC shut down by Windows): asks before cycling it', () async {
      remote.plugOn = true;

      expect(await pc.powerOn(), PowerOnResult.needsPlugCycle);
      expect(remote.calls, ['plug?']);
      expect(pc.phase, PcPhase.off);

      final before = now;
      expect(await pc.powerOn(cyclePlug: true), PowerOnResult.started);

      expect(remote.calls, ['plug?', 'plug?', 'plug:off', 'plug:on']);
      expect(now.difference(before), PcController.plugCycleGap);
      expect(pc.phase, PcPhase.booting);
    });

    test('Home Assistant unreachable: nothing changes', () async {
      remote.plugOn = null;

      expect(await pc.powerOn(), PowerOnResult.failed);
      await Future<void>.delayed(Duration.zero);

      expect(remote.calls, ['plug?']);
      expect(pc.phase, PcPhase.off);
      expect(messages.single.isError, isTrue);
    });

    test('no heartbeat within the boot timeout goes back to off with an error', () async {
      await pc.powerOn();

      await advance(const Duration(minutes: 2));
      expect(pc.phase, PcPhase.booting);
      await advance(const Duration(minutes: 1, seconds: 1));

      expect(pc.phase, PcPhase.off);
      expect(messages.last.isError, isTrue);
    });
  });

  group('spegnimento', () {
    setUp(() async => startOnline());

    CommandResult shutdownResult(String status, [String? message]) =>
        CommandResult(id: remote.lastCommandId!, status: status, message: message);

    test('sends SHUTDOWN, then cuts the plug 60 s after the PC disappears', () async {
      await pc.shutdown();
      expect(remote.calls, ['pc:SHUTDOWN']);
      expect(pc.phase, PcPhase.shuttingDown);

      remote.pcResult = shutdownResult('OK', 'spegnimento tra 10s');
      await advance(const Duration(seconds: 2), pcAlive: true);
      expect(pc.shutdownStatus, 'Windows si sta spegnendo...');
      expect(pc.ledsOn, isTrue);

      await advance(const Duration(seconds: 15)); // agent chiuso da Windows
      expect(pc.ledsOn, isFalse);
      await advance(const Duration(seconds: 59));
      expect(remote.calls, isNot(contains('plug:off')));

      await advance(const Duration(seconds: 2));
      expect(remote.calls, ['pc:SHUTDOWN', 'plug:off']);
      expect(pc.phase, PcPhase.off);
      expect(messages.last.text, contains('presa staccata'));
    });

    test('agent gone before publishing OK still counts as shutting down', () async {
      await pc.shutdown();

      await advance(const Duration(seconds: 15));
      await advance(const Duration(seconds: 61));

      expect(remote.calls.last, 'plug:off');
      expect(pc.phase, PcPhase.off);
    });

    test('refused by the agent: back online, plug untouched', () async {
      await pc.shutdown();
      remote.pcResult = shutdownResult('ERRORE', 'shutdown rifiutato: accesso negato');

      await advance(const Duration(seconds: 2), pcAlive: true);

      expect(pc.phase, PcPhase.online);
      expect(messages.last.text, contains('accesso negato'));
      expect(remote.calls, ['pc:SHUTDOWN']);
    });

    test('PC still on after the shutdown timeout keeps the plug on', () async {
      await pc.shutdown();
      remote.pcResult = shutdownResult('OK');
      await advance(const Duration(seconds: 2), pcAlive: true);

      for (var i = 0; i < 4; i++) {
        await advance(const Duration(seconds: 50), pcAlive: true);
      }

      expect(pc.phase, PcPhase.online);
      expect(messages.last.isError, isTrue);
      expect(remote.calls, ['pc:SHUTDOWN']);
    });

    test('command not written: stays online', () async {
      remote.commandsOk = false;

      await pc.shutdown();

      expect(pc.phase, PcPhase.online);
    });
  });

  group('app', () {
    setUp(() async => startOnline());

    test('START is sent and its result from the PC closes the wait', () async {
      await pc.toggleApp('antigravity');

      expect(remote.calls, ['app:antigravity:START']);
      expect(pc.isBusy('antigravity'), isTrue);

      remote.appResults['antigravity'] =
          CommandResult(id: remote.lastCommandId!, status: 'OK', message: 'avviato');
      remote.appStates['antigravity'] = 'RUNNING';
      await advance(const Duration(seconds: 3), pcAlive: true);

      expect(pc.isBusy('antigravity'), isFalse);
      expect(pc.app('antigravity').isRunning, isTrue);
      expect(messages.last.text, 'Antigravity 2.0: avviato.');
    });

    test('running app gets STOP', () async {
      remote.appStates['claude'] = 'RUNNING';
      await advance(Duration.zero, pcAlive: true);

      await pc.toggleApp('claude');

      expect(remote.calls, ['app:claude:STOP']);
    });

    test('no answer within 60 s is reported', () async {
      await pc.toggleApp('antigravity');

      for (var i = 0; i < 7; i++) {
        await advance(const Duration(seconds: 9), pcAlive: true);
      }

      expect(pc.isBusy('antigravity'), isFalse);
      expect(messages.last.text, contains('nessuna risposta'));
    });
  });
}
