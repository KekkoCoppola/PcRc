class PcStatus {
  final int? lastSeen;
  final bool? online;
  final DateTime fetchTime;

  PcStatus({
    this.lastSeen,
    this.online,
    required this.fetchTime,
  });

  factory PcStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return PcStatus(fetchTime: DateTime.now());
    }

    int? parsedLastSeen;
    final rawLastSeen = json['last_seen'];
    if (rawLastSeen is int) {
      // If it's in milliseconds (> 10000000000), convert to seconds
      parsedLastSeen = rawLastSeen > 10000000000 ? rawLastSeen ~/ 1000 : rawLastSeen;
    } else if (rawLastSeen is num) {
      parsedLastSeen = rawLastSeen.toInt();
      if (parsedLastSeen > 10000000000) parsedLastSeen ~/= 1000;
    } else if (rawLastSeen is String) {
      parsedLastSeen = int.tryParse(rawLastSeen);
    }

    final rawOnline = json['online'];
    bool? parsedOnline;
    if (rawOnline is bool) {
      parsedOnline = rawOnline;
    }

    return PcStatus(
      lastSeen: parsedLastSeen,
      online: parsedOnline,
      fetchTime: DateTime.now(),
    );
  }

  /// Calculates whether PC is online.
  /// Rule: if last_seen is within the last 10 seconds of current UTC time.
  bool get isOnline {
    if (lastSeen == null) return false;
    final int nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final diff = nowSeconds - lastSeen!;
    // Consider online if within last 10 seconds (with tolerance for small device clock skew)
    return diff >= -2 && diff <= 10;
  }

  /// Seconds elapsed since last seen
  int? get secondsAgo {
    if (lastSeen == null) return null;
    final int nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final diff = nowSeconds - lastSeen!;
    return diff < 0 ? 0 : diff;
  }

  String get formattedStatus {
    if (lastSeen == null) return 'Nessun segnale';
    final sec = secondsAgo;
    if (sec == null) return 'Sconosciuto';
    if (sec <= 10) return 'Online (attivo ora)';
    if (sec < 60) return 'Offline (${sec}s fa)';
    final minutes = sec ~/ 60;
    if (minutes < 60) return 'Offline (${minutes}m fa)';
    final hours = minutes ~/ 60;
    return 'Offline (${hours}h fa)';
  }
}
