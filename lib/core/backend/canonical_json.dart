import 'dart:convert';

/// JSON encode with map keys sorted recursively (for stable content hashes).
String canonicalJson(Object? value) {
  return jsonEncode(_canonicalize(value));
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    final out = <String, Object?>{};
    for (final k in keys) {
      out[k] = _canonicalize(value[k]);
    }
    return out;
  }
  if (value is List) {
    return value.map(_canonicalize).toList();
  }
  return value;
}