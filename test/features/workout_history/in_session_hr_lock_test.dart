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

    test('types 6/8/140 stay empty even when bytes look like 0x23 run records',
        () {
      final pages = [_page([_rec(hr: 140), _rec(hr: 150)])];
      expect(lockInSessionHrPoints(pages, workoutType: 6), isEmpty);
      expect(lockInSessionHrPoints(pages, workoutType: 8), isEmpty);
      expect(lockInSessionHrPoints(pages, workoutType: 140), isEmpty);
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
}

List<int> _rec({int marker = 0x23, int cadence = 100, required int hr}) =>
    [0x00, 0x00, marker, cadence, hr, 0x00, 0x0D, 0x08];

PeeledPageBodies _page(List<List<int>> records) {
  final bytes = [for (final r in records) ...r];
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
