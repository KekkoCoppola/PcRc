class AppInfo {
  final String key;
  final String displayName;
  final String actualState;
  final bool isMutating;
  // Esito dell'ultimo comando, pubblicato dall'agent sul PC in apps/<key>/result
  final String? resultId;
  final String? resultStatus;
  final String? resultMessage;

  AppInfo({
    required this.key,
    required this.displayName,
    required this.actualState,
    this.isMutating = false,
    this.resultId,
    this.resultStatus,
    this.resultMessage,
  });

  bool get isRunning => actualState.toUpperCase() == 'RUNNING';

  AppInfo copyWith({
    String? key,
    String? displayName,
    String? actualState,
    bool? isMutating,
    String? resultId,
    String? resultStatus,
    String? resultMessage,
  }) {
    return AppInfo(
      key: key ?? this.key,
      displayName: displayName ?? this.displayName,
      actualState: actualState ?? this.actualState,
      isMutating: isMutating ?? this.isMutating,
      resultId: resultId ?? this.resultId,
      resultStatus: resultStatus ?? this.resultStatus,
      resultMessage: resultMessage ?? this.resultMessage,
    );
  }

  factory AppInfo.fromJson(String key, String displayName, Map<String, dynamic>? json) {
    if (json == null) {
      return AppInfo(
        key: key,
        displayName: displayName,
        actualState: 'STOPPED',
      );
    }

    final actual = (json['actual_state'] ?? 'STOPPED').toString().toUpperCase();
    final result = json['result'] is Map<String, dynamic>
        ? json['result'] as Map<String, dynamic>
        : null;

    return AppInfo(
      key: key,
      displayName: displayName,
      actualState: actual,
      resultId: result?['id']?.toString(),
      resultStatus: result?['status']?.toString(),
      resultMessage: result?['message']?.toString(),
    );
  }
}
