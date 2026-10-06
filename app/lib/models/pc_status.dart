/// Heartbeat del PC: l'agent scrive `pc_status/last_seen` (secondi epoch) ogni 2 s.
class PcStatus {
  const PcStatus({this.lastSeen});

  /// Secondi epoch dell'ultimo heartbeat, null se il PC non si è mai fatto sentire.
  final int? lastSeen;

  /// Oltre questo silenzio il PC è considerato spento.
  static const onlineWindow = Duration(seconds: 10);

  factory PcStatus.fromJson(Object? json) {
    if (json is! Map) return const PcStatus();
    final raw = json['last_seen'];
    int? seconds;
    if (raw is num) {
      seconds = raw.toInt();
    } else if (raw is String) {
      seconds = int.tryParse(raw);
    }
    // Tollera valori in millisecondi
    if (seconds != null && seconds > 10000000000) seconds ~/= 1000;
    return PcStatus(lastSeen: seconds);
  }

  /// Secondi trascorsi dall'ultimo heartbeat (negativo se l'orologio del telefono è indietro).
  int? secondsAgoAt(DateTime now) {
    if (lastSeen == null) return null;
    return now.millisecondsSinceEpoch ~/ 1000 - lastSeen!;
  }

  /// Online se l'ultimo heartbeat è recente (tollera 2 s di orologi sfasati).
  bool isOnlineAt(DateTime now) {
    final ago = secondsAgoAt(now);
    return ago != null && ago >= -2 && ago <= onlineWindow.inSeconds;
  }

  String describeAt(DateTime now) {
    final ago = secondsAgoAt(now);
    if (ago == null) return 'Nessun segnale';
    if (isOnlineAt(now)) return 'Online (attivo ora)';
    final sec = ago < 0 ? 0 : ago;
    if (sec < 60) return 'Offline (${sec}s fa)';
    final minutes = sec ~/ 60;
    if (minutes < 60) return 'Offline (${minutes}m fa)';
    final hours = minutes ~/ 60;
    if (hours < 48) return 'Offline (${hours}h fa)';
    return 'Offline (${hours ~/ 24}g fa)';
  }
}
