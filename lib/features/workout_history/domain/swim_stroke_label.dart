/// Huawei swimming_stroke vocabulary shared by detail UI and capability logs.
///
/// Wire codes: 1 breast, 2 free, 3 fly, 4 back, 5 medley.
library;

const Map<int, String> kSwimStrokeLabels = <int, String>{
  1: 'Breaststroke',
  2: 'Freestyle',
  3: 'Butterfly',
  4: 'Backstroke',
  5: 'Medley',
};

/// Human-readable stroke label for [style] code.
///
/// Known 1–5 → map names. Unknown codes → `Stroke $n` (raw numeric included).
/// Null → stable non-empty `"null"` (does not invent a stroke name).
String swimStrokeLabel(int? style) {
  if (style == null) return 'null';
  return kSwimStrokeLabels[style] ?? 'Stroke $style';
}
