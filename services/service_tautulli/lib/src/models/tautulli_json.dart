/// Tolerant JSON converters for Tautulli's stringly-typed API.
///
/// Tautulli renders most numbers as strings, and the same field can arrive
/// as `"77"`, `77`, `null`, or `""` depending on server version and player.
/// Every model field goes through these so a type drift never crashes a
/// whole screen (the Prowlarr `tags` lesson).
library;

String tString(dynamic v) => v?.toString() ?? '';

int tInt(dynamic v) {
  if (v == null) {
    return 0;
  }
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  return int.tryParse(v.toString()) ?? (double.tryParse(v.toString())?.toInt() ?? 0);
}

double tDouble(dynamic v) {
  if (v == null) {
    return 0;
  }
  if (v is num) {
    return v.toDouble();
  }
  return double.tryParse(v.toString()) ?? 0;
}
