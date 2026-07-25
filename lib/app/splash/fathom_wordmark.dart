import 'package:flutter/material.dart';

/// Geometric Fa + Discobolus-as-T + hom wordmark (splash / brand moment).
///
/// Letter geometry matches `docs/design/logo.html` SVG symbols. The athlete
/// image fills the T slot only — never used as the launcher icon.
class FathomWordmark extends StatelessWidget {
  const FathomWordmark({
    super.key,
    required this.height,
    required this.color,
    required this.athleteScale,
    required this.faOpacity,
    required this.homOpacity,
    required this.lettersOffsetY,
    this.athleteAsset = 'assets/brand/discobolus.png',
    this.invertAthlete = false,
  });

  final double height;
  final Color color;
  final double athleteScale;
  final double faOpacity;
  final double homOpacity;
  final double lettersOffsetY;
  final String athleteAsset;
  final bool invertAthlete;

  static const double _markSlotWidthFactor = 0.78;
  static const double _markSideGapFactor = 0.12;

  @override
  Widget build(BuildContext context) {
    final markWidth = height * _markSlotWidthFactor;
    final sideGap = height * _markSideGapFactor;
    final faWidth = height * (52 / 36);
    final homWidth = height * (92 / 36);

    Widget athlete = Image.asset(
      athleteAsset,
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        Icons.accessibility_new,
        size: height * 0.85,
        color: color,
      ),
    );
    if (invertAthlete) {
      athlete = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          -1, 0, 0, 0, 255, //
          0, -1, 0, 0, 255, //
          0, 0, -1, 0, 255, //
          0, 0, 0, 1, 0,
        ]),
        child: athlete,
      );
    }

    return Semantics(
      label: 'Fathom',
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Opacity(
              opacity: faOpacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, lettersOffsetY),
                child: CustomPaint(
                  size: Size(faWidth, height),
                  painter: _SvgSymbolPainter(
                    color: color,
                    viewBox: const Size(52, 36),
                    paths: _faPaths,
                  ),
                ),
              ),
            ),
            SizedBox(width: sideGap),
            SizedBox(
              width: markWidth,
              child: Padding(
                padding: EdgeInsets.only(
                  top: height * 0.08,
                  bottom: height * 0.14,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Transform.scale(
                    scale: athleteScale,
                    alignment: Alignment.bottomCenter,
                    child: athlete,
                  ),
                ),
              ),
            ),
            SizedBox(width: sideGap),
            Opacity(
              opacity: homOpacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, lettersOffsetY),
                child: CustomPaint(
                  size: Size(homWidth, height),
                  painter: _SvgSymbolPainter(
                    color: color,
                    viewBox: const Size(92, 36),
                    paths: _homPaths,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paths from `docs/design/logo.html` `#letters-fa` / `#letters-hom`.
const List<String> _faPaths = <String>[
  'M4 4h20v4.4H9.2v7.6H20.4v4.4H9.2V32H4V4z',
  'M40.2 13.8c-5.5 0-9.5 3.7-9.5 9.1 0 5.5 4 9.1 9.6 9.1 3 0 5.4-1 7.1-2.8v2.5h4.2V13.8h-4.2v2.2c-1.5-1.4-3.5-2.2-7.2-2.2zm.5 14.3c-3.2 0-5.4-2.2-5.4-5.2s2.2-5.2 5.4-5.2 5.4 2.2 5.4 5.2-2.2 5.2-5.4 5.2z',
];

const List<String> _homPaths = <String>[
  'M4 4h4.4v11c1.5-1.5 3.6-2.5 6.5-2.5 5.3 0 8.9 3.6 8.9 9.3V32h-4.4v-9.3c0-3.4-1.9-5.5-5-5.5-3.3 0-5.6 2.3-5.6 5.7V32H4V4z',
  'M38.4 13.6c-5.5 0-9.6 4-9.6 9.2s4.1 9.2 9.6 9.2 9.6-4 9.6-9.2-4.1-9.2-9.6-9.2zm0 14.4c-3.1 0-5.3-2.3-5.3-5.2s2.2-5.2 5.3-5.2 5.3 2.3 5.3 5.2-2.2 5.2-5.3 5.2z',
  'M54.2 14.2h4.3v2.3c1.4-1.6 3.4-2.8 6.3-2.8 2.5 0 4.5 1 5.8 2.6 1.5-1.6 3.7-2.6 6.6-2.6 5 0 8.2 3.3 8.2 8.7V32h-4.3v-9c0-3.1-1.6-5-4.3-5-2.8 0-4.6 2-4.6 5.2V32h-4.3v-9c0-3.1-1.6-5-4.3-5-2.8 0-4.7 2.1-4.7 5.4V32h-4.3V14.2z',
];

class _SvgSymbolPainter extends CustomPainter {
  _SvgSymbolPainter({
    required this.color,
    required this.viewBox,
    required this.paths,
  });

  final Color color;
  final Size viewBox;
  final List<String> paths;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / viewBox.width;
    final scaleY = size.height / viewBox.height;
    canvas.save();
    canvas.scale(scaleX, scaleY);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (final d in paths) {
      canvas.drawPath(_parseSvgPath(d), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SvgSymbolPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.viewBox != viewBox ||
        oldDelegate.paths != paths;
  }
}

/// Minimal SVG path parser for the locked letter marks (M/H/V/C/S/Z + relatives).
Path _parseSvgPath(String d) {
  final path = Path();
  final tokens = _tokenize(d);
  var i = 0;
  var cmd = '';
  double cx = 0, cy = 0;
  double startX = 0, startY = 0;
  double? lastCx, lastCy;

  double next() => double.parse(tokens[i++]);
  bool hasNumber() => i < tokens.length && !_isCommand(tokens[i]);

  while (i < tokens.length) {
    if (_isCommand(tokens[i])) {
      cmd = tokens[i++];
    }
    if (cmd.isEmpty) {
      throw FormatException('SVG path missing command near: ${tokens[i]}');
    }

    if (cmd == 'M' || cmd == 'm') {
      final relative = cmd == 'm';
      cx = relative ? cx + next() : next();
      cy = relative ? cy + next() : next();
      path.moveTo(cx, cy);
      startX = cx;
      startY = cy;
      lastCx = lastCy = null;
      // Implicit line-tos after an initial moveto pair.
      cmd = relative ? 'l' : 'L';
      while (hasNumber()) {
        cx = relative ? cx + next() : next();
        cy = relative ? cy + next() : next();
        path.lineTo(cx, cy);
      }
    } else if (cmd == 'L' || cmd == 'l') {
      while (hasNumber()) {
        final relative = cmd == 'l';
        cx = relative ? cx + next() : next();
        cy = relative ? cy + next() : next();
        path.lineTo(cx, cy);
        lastCx = lastCy = null;
      }
    } else if (cmd == 'H' || cmd == 'h') {
      while (hasNumber()) {
        cx = cmd == 'h' ? cx + next() : next();
        path.lineTo(cx, cy);
        lastCx = lastCy = null;
      }
    } else if (cmd == 'V' || cmd == 'v') {
      while (hasNumber()) {
        cy = cmd == 'v' ? cy + next() : next();
        path.lineTo(cx, cy);
        lastCx = lastCy = null;
      }
    } else if (cmd == 'C' || cmd == 'c') {
      while (hasNumber()) {
        final relative = cmd == 'c';
        final x1 = relative ? cx + next() : next();
        final y1 = relative ? cy + next() : next();
        final x2 = relative ? cx + next() : next();
        final y2 = relative ? cy + next() : next();
        final x = relative ? cx + next() : next();
        final y = relative ? cy + next() : next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
        cx = x;
        cy = y;
      }
    } else if (cmd == 'S' || cmd == 's') {
      while (hasNumber()) {
        final relative = cmd == 's';
        final x1 = lastCx == null ? cx : 2 * cx - lastCx;
        final y1 = lastCy == null ? cy : 2 * cy - lastCy;
        final x2 = relative ? cx + next() : next();
        final y2 = relative ? cy + next() : next();
        final x = relative ? cx + next() : next();
        final y = relative ? cy + next() : next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
        cx = x;
        cy = y;
      }
    } else if (cmd == 'Z' || cmd == 'z') {
      path.close();
      cx = startX;
      cy = startY;
      lastCx = lastCy = null;
    } else {
      throw FormatException('Unsupported SVG path command: $cmd');
    }
  }
  return path;
}

List<String> _tokenize(String d) {
  final out = <String>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      out.add(buf.toString());
      buf.clear();
    }
  }

  for (var i = 0; i < d.length; i++) {
    final ch = d[i];
    if (_isCommand(ch)) {
      flush();
      out.add(ch);
    } else if (ch == ',' || ch == ' ' || ch == '\n' || ch == '\t') {
      flush();
    } else if (ch == '-' && buf.isNotEmpty) {
      final soFar = buf.toString();
      if (!soFar.endsWith('e') && !soFar.endsWith('E')) {
        flush();
      }
      buf.write(ch);
    } else {
      buf.write(ch);
    }
  }
  flush();
  return out;
}

bool _isCommand(String t) =>
    t.length == 1 && 'MmLlHhVvCcSsZz'.contains(t);
