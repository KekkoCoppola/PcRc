import 'package:pcrc/models/app_info.dart';
import 'package:pcrc/models/command_result.dart';
import 'package:pcrc/models/managed_app.dart';
import 'package:pcrc/models/pc_status.dart';
import 'package:pcrc/models/remote_snapshot.dart';
import 'package:pcrc/services/pc_remote.dart';

/// Firebase + Home Assistant in memoria. [calls] registra i comandi in ordine:
/// `plug?`, `plug:on`, `plug:off`, `pc:SHUTDOWN`, `app:<key>:START|STOP`.
class FakeRemote implements PcRemote {
  int? lastSeen;
  final Map<String, String> appStates = {};
  final Map<String, CommandResult> appResults = {};
  CommandResult? pcResult;
  bool firebaseUp = true;
  bool commandsOk = true;

  /// Stato della presa; null = Home Assistant non risponde.
  bool? plugOn = false;
  bool setPlugOk = true;

  final List<String> calls = [];
  String? lastCommandId;
  int _ids = 0;

  void heartbeat(DateTime at) => lastSeen = at.millisecondsSinceEpoch ~/ 1000;

  @override
  Future<RemoteSnapshot?> fetchSnapshot() async {
    if (!firebaseUp) return null;
    return RemoteSnapshot(
      pcStatus: PcStatus(lastSeen: lastSeen),
      apps: {
        for (final app in managedApps)
          app.key: AppInfo(
            key: app.key,
            actualState: appStates[app.key] ?? 'STOPPED',
            result: appResults[app.key],
          ),
      },
      pcResult: pcResult,
    );
  }

  @override
  Future<String?> sendAppCommand(String appKey, String action) async {
    calls.add('app:$appKey:$action');
    return _newId();
  }

  @override
  Future<String?> sendPcCommand(String action) async {
    calls.add('pc:$action');
    return _newId();
  }

  String? _newId() {
    if (!commandsOk) return null;
    return lastCommandId = 'cmd${++_ids}';
  }

  @override
  Future<bool?> fetchPlugOn() async {
    calls.add('plug?');
    return plugOn;
  }

  @override
  Future<bool> setPlug(bool on) async {
    calls.add(on ? 'plug:on' : 'plug:off');
    if (setPlugOk) plugOn = on;
    return setPlugOk;
  }

  @override
  void dispose() {}
}
