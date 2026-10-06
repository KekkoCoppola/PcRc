/// Esito di un comando, pubblicato dall'agent sul PC in `<nodo>/result`
/// con lo stesso id del comando (`apps/<app>/result` oppure `pc/result`).
class CommandResult {
  const CommandResult({required this.id, required this.status, this.message});

  final String id;

  /// IN_CORSO, poi OK, ERRORE o SCARTATO.
  final String status;
  final String? message;

  static CommandResult? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final status = json['status'];
    if (id == null || status == null) return null;
    return CommandResult(
      id: id.toString(),
      status: status.toString(),
      message: json['message']?.toString(),
    );
  }
}
