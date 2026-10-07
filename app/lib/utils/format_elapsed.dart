/// Durata compatta per gli stati: "12s", "52m", "3h 05m", "2g 4h".
String formatElapsed(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  return '${d.inDays}g ${d.inHours % 24}h';
}
