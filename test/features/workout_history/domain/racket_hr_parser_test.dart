import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/in_session_hr_lock.dart';
import 'package:fitness_os/features/workout_history/domain/run_session_metrics.dart';

void main() {
  group('Racket sport HR parsing', () {
    test('decodeRacketPackedHrPoints parses consecutive u8 BPM at 1s', () {
      // Simulate 10 seconds of HR data: 82, 85, 87, 90, 92, 95, 98, 100, 102, 105
      final hrBytes = [82, 85, 87, 90, 92, 95, 98, 100, 102, 105];
      final bodyBase64 = base64Encode(hrBytes);

      final pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x05, len: hrBytes.length, bodyBase64: bodyBase64),
          ],
        ),
      ];

      final points = decodeRacketPackedHrPoints(pages);

      expect(points, hasLength(10));
      expect(points[0].offsetSec, 0);
      expect(points[0].hrBpm, 82);
      expect(points[5].offsetSec, 5);
      expect(points[5].hrBpm, 95);
      expect(points[9].offsetSec, 9);
      expect(points[9].hrBpm, 105);
    });

    test('decodeRacketPackedHrPoints filters out-of-range HR values', () {
      // Mix valid and invalid HR values
      final hrBytes = [30, 82, 85, 250, 92, 95, 0, 100, 102, 255];
      final bodyBase64 = base64Encode(hrBytes);

      final pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x05, len: hrBytes.length, bodyBase64: bodyBase64),
          ],
        ),
      ];

      final points = decodeRacketPackedHrPoints(pages);

      expect(points, hasLength(10));
      expect(points[0].hrBpm, isNull); // 30 too low
      expect(points[1].hrBpm, 82); // valid
      expect(points[3].hrBpm, isNull); // 250 too high
      expect(points[6].hrBpm, isNull); // 0 invalid
      expect(points[7].hrBpm, 100); // valid
      expect(points[9].hrBpm, isNull); // 255 too high
    });

    test('decodeRacketPackedHrPoints returns empty for no 0x05 bodies', () {
      final pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x04, len: 4, bodyBase64: base64Encode([1, 2, 3, 4])),
          ],
        ),
      ];

      final points = decodeRacketPackedHrPoints(pages);
      expect(points, isEmpty);
    });

    test('decodeRacketPackedHrPoints concatenates multiple pages', () {
      final page1Hr = [80, 82, 85];
      final page2Hr = [90, 95, 100];

      final pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x05, len: page1Hr.length, bodyBase64: base64Encode(page1Hr)),
          ],
        ),
        PeeledPageBodies(
          index: 1,
          bodies: [
            LeftoverTlvBody(id: 0x05, len: page2Hr.length, bodyBase64: base64Encode(page2Hr)),
          ],
        ),
      ];

      final points = decodeRacketPackedHrPoints(pages);

      expect(points, hasLength(6));
      expect(points[0].hrBpm, 80);
      expect(points[2].hrBpm, 85);
      expect(points[3].hrBpm, 90);
      expect(points[5].hrBpm, 100);
    });

    test('lockInSessionHrPoints uses racket parser for badminton (129)', () {
      final hrBytes = [82, 85, 87, 90, 92];
      final bodyBase64 = base64Encode(hrBytes);

      final pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x05, len: hrBytes.length, bodyBase64: bodyBase64),
          ],
        ),
      ];

      final points = lockInSessionHrPoints(
        pages,
        workoutType: 129, // Badminton
        hrMin: 82,
        hrMax: 92,
      );

      expect(points, isNotEmpty);
      expect(points.first.hrBpm, 82);
      expect(points.last.hrBpm, 92);
    });

    test('lockInSessionHrPoints uses racket parser for tennis (131)', () {
      final hrBytes = [90, 95, 100, 105];
      final bodyBase64 = base64Encode(hrBytes);

      final pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x05, len: hrBytes.length, bodyBase64: bodyBase64),
          ],
        ),
      ];

      final points = lockInSessionHrPoints(
        pages,
        workoutType: 131, // Tennis
        hrMin: 90,
        hrMax: 105,
      );

      expect(points, isNotEmpty);
      expect(points.first.hrBpm, 90);
    });

    test('lockInSessionHrPoints rejects mismatched HR min/max', () {
      final hrBytes = [82, 85, 87, 90, 92];
      final bodyBase64 = base64Encode(hrBytes);

      final pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x05, len: hrBytes.length, bodyBase64: bodyBase64),
          ],
        ),
      ];

      // Wrong hrMin (series min is 82, claimed min is 70)
      final points = lockInSessionHrPoints(
        pages,
        workoutType: 129,
        hrMin: 70,
        hrMax: 92,
      );

      expect(points, isEmpty); // Lock fails on min mismatch
    });

    test('lockInSessionHrPoints accepts within tolerance', () {
      final hrBytes = [82, 85, 87, 90, 92];
      final bodyBase64 = base64Encode(hrBytes);

      final pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x05, len: hrBytes.length, bodyBase64: bodyBase64),
          ],
        ),
      ];

      // Within 1 bpm tolerance (series min is 82, claimed 81)
      final points = lockInSessionHrPoints(
        pages,
        workoutType: 129,
        hrMin: 81,
        hrMax: 93,
        agreementToleranceBpm: 1,
      );

      expect(points, isNotEmpty);
    });

    test('racket sport uses 1-second interval (not 5-second like strength)', () {
      final hrBytes = [80, 85, 90, 95, 100]; // 5 samples
      final bodyBase64 = base64Encode(hrBytes);

      final pages = [
        PeeledPageBodies(
          index: 0,
          bodies: [
            LeftoverTlvBody(id: 0x05, len: hrBytes.length, bodyBase64: bodyBase64),
          ],
        ),
      ];

      final points = decodeRacketPackedHrPoints(pages);

      expect(points, hasLength(5));
      expect(points[0].offsetSec, 0);
      expect(points[1].offsetSec, 1); // 1-second interval
      expect(points[2].offsetSec, 2);
      expect(points[4].offsetSec, 4);
    });
  });
}
