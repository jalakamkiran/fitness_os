import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/in_session_hr_lock.dart';

void main() {
  group('lockInSessionHrPoints', () {
    test('catalogued marker + two in-band HR values locks at 5 s offsets', () {
      final points = lockInSessionHrPoints(
        [_page([_rec(hr: 140), _rec(hr: 150)])],
        workoutType: 2,
      );
      expect(points, hasLength(2));
      expect(points[0].offsetSec, 0);
      expect(points[0].hrBpm, 140);
      expect(points[0].cadenceSpm, isNull);
      expect(points[1].offsetSec, 5);
      expect(points[1].hrBpm, 150);
    });

    test('single in-band HR sample omits', () {
      expect(
        lockInSessionHrPoints(
          [_page([_rec(hr: 140)])],
          workoutType: 2,
        ),
        isEmpty,
      );
    });

    test('hrMin/hrMax matching extrema within 1 bpm locks', () {
      final points = lockInSessionHrPoints(
        [_page([_rec(hr: 140), _rec(hr: 150)])],
        workoutType: 2,
        hrMin: 140,
        hrMax: 151,
      );
      expect(points.map((p) => p.hrBpm), [140, 150]);
    });

    test('types 6/8 stay empty for run-shaped 8-byte records', () {
      final pages = [_page([_rec(hr: 140), _rec(hr: 150)])];
      expect(lockInSessionHrPoints(pages, workoutType: 6), isEmpty);
      expect(lockInSessionHrPoints(pages, workoutType: 8), isEmpty);
    });

    test('type 6 swim 7-byte records lock at 5 s with totals agreement', () {
      // Session #67 shape: HR 00 A 00 B 00 C, first byte BPM.
      final body = <int>[
        76, 0, 5, 0, 79, 0, 18,
        79, 0, 5, 0, 79, 0, 18,
        153, 0, 3, 0, 120, 0, 12,
      ];
      final points = lockInSessionHrPoints(
        [_packedPage(body)],
        workoutType: 6,
        hrMin: 76,
        hrMax: 153,
      );
      expect(points.map((p) => p.hrBpm), [76, 79, 153]);
      expect(points.map((p) => p.offsetSec), [0, 5, 10]);
    });

    test('type 8 open water uses the same 7-byte swim packing', () {
      final body = <int>[
        80, 0, 4, 0, 70, 0, 10,
        90, 0, 4, 0, 70, 0, 10,
      ];
      expect(
        lockInSessionHrPoints(
          [_packedPage(body)],
          workoutType: 8,
          hrMin: 80,
          hrMax: 90,
        ).map((p) => p.hrBpm),
        [80, 90],
      );
    });

    test('type 6 with totals disagreement omits', () {
      final body = <int>[
        76, 0, 5, 0, 79, 0, 18,
        100, 0, 5, 0, 79, 0, 18,
      ];
      expect(
        lockInSessionHrPoints(
          [_packedPage(body)],
          workoutType: 6,
          hrMin: 50,
          hrMax: 60,
        ),
        isEmpty,
      );
    });

    test('type 6 truncated mid-record omits', () {
      expect(
        lockInSessionHrPoints(
          [_packedPage([76, 0, 5, 0, 79, 0])], // 6 bytes, not 7
          workoutType: 6,
        ),
        isEmpty,
      );
    });

    test('type 140 with fewer than two in-band BPM bytes omits', () {
      expect(
        lockInSessionHrPoints(
          [_packedPage([0x00, 10, 84])],
          workoutType: 140,
        ),
        isEmpty,
      );
    });

    test('type 140 packed BPM series locks at 5 s with totals agreement', () {
      // Session #70 shape: leading 0x00 pad then consecutive BPM.
      final body = [0x00, 84, 90, 100, 110, 120, 135];
      final points = lockInSessionHrPoints(
        [_packedPage(body)],
        workoutType: 140,
        hrMin: 84,
        hrMax: 135,
      );
      expect(points.where((p) => p.hrBpm != null).length, 6);
      expect(points.first.hrBpm, isNull);
      expect(points[1].offsetSec, 5);
      expect(points[1].hrBpm, 84);
      expect(points.last.hrBpm, 135);
      expect(points.last.offsetSec, 30);
    });

    test('type 140 packed series disagrees with totals omits', () {
      expect(
        lockInSessionHrPoints(
          [_packedPage([84, 90, 100])],
          workoutType: 140,
          hrMin: 50,
          hrMax: 60,
        ),
        isEmpty,
      );
    });

    test('plausible bpm with totals absent still locks', () {
      expect(
        lockInSessionHrPoints(
          [_page([_rec(hr: 90), _rec(hr: 110)])],
          workoutType: 2,
        ),
        hasLength(2),
      );
    });

    test('totals min/max present and series disagrees omits', () {
      expect(
        lockInSessionHrPoints(
          [_page([_rec(hr: 140), _rec(hr: 150)])],
          workoutType: 2,
          hrMin: 80,
          hrMax: 90,
        ),
        isEmpty,
      );
    });

    test('only hrMin present checks min only', () {
      expect(
        lockInSessionHrPoints(
          [_page([_rec(hr: 140), _rec(hr: 180)])],
          workoutType: 2,
          hrMin: 140,
        ),
        hasLength(2),
      );
      expect(
        lockInSessionHrPoints(
          [_page([_rec(hr: 140), _rec(hr: 180)])],
          workoutType: 2,
          hrMin: 80,
        ),
        isEmpty,
      );
    });

    test('hrPeak-only is not a totals bound', () {
      // Lock API has no hrPeak argument — peak on the row must not reject.
      expect(
        lockInSessionHrPoints(
          [_page([_rec(hr: 100), _rec(hr: 120)])],
          workoutType: 2,
        ),
        hasLength(2),
      );
    });

    test('empty pages, non-0x05 leftovers, truncated body omit', () {
      expect(lockInSessionHrPoints(const [], workoutType: 2), isEmpty);
      expect(
        lockInSessionHrPoints(const [
          PeeledPageBodies(
            index: 0,
            bodies: [
              LeftoverTlvBody(id: 0x66, len: 8, bodyBase64: 'AAAAAAAAAAA='),
            ],
          ),
        ], workoutType: 2),
        isEmpty,
      );
      expect(
        lockInSessionHrPoints([
          PeeledPageBodies(
            index: 0,
            bodies: [
              LeftoverTlvBody(
                id: 0x05,
                len: 4,
                bodyBase64: base64Encode(const [0x00, 0x00, 0x23, 100]),
              ),
            ],
          ),
        ], workoutType: 2),
        isEmpty,
      );
    });
  });

  group('decodeStrengthPackedHrPoints', () {
    test('maps consecutive bytes to 5 s offsets', () {
      final points = decodeStrengthPackedHrPoints([
        _packedPage([92, 96, 98]),
      ]);
      expect(points.map((p) => p.hrBpm), [92, 96, 98]);
      expect(points.map((p) => p.offsetSec), [0, 5, 10]);
    });
  });
}

List<int> _rec({int marker = 0x23, int cadence = 100, required int hr}) =>
    [0x00, 0x00, marker, cadence, hr, 0x00, 0x0D, 0x08];

PeeledPageBodies _page(List<List<int>> records) {
  final bytes = [for (final r in records) ...r];
  return _packedPage(bytes);
}

PeeledPageBodies _packedPage(List<int> bytes) {
  return PeeledPageBodies(
    index: 0,
    bodies: [
      LeftoverTlvBody(
        id: 0x05,
        len: bytes.length,
        bodyBase64: base64Encode(bytes),
      ),
    ],
  );
}
