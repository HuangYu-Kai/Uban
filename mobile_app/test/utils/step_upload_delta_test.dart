import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/utils/step_upload_delta.dart';

void main() {
  group('restoreUploadedSteps', () {
    test('同一天沿用已存值', () {
      expect(
          restoreUploadedSteps(
              storedSteps: 3200, storedDate: '2026-10-07', today: '2026-10-07'),
          3200);
    });
    test('跨日歸零', () {
      expect(
          restoreUploadedSteps(
              storedSteps: 3200, storedDate: '2026-10-06', today: '2026-10-07'),
          0);
    });
    test('從未存過或負值歸零', () {
      expect(
          restoreUploadedSteps(
              storedSteps: null, storedDate: null, today: '2026-10-07'),
          0);
      expect(
          restoreUploadedSteps(
              storedSteps: -5, storedDate: '2026-10-07', today: '2026-10-07'),
          0);
      expect(
          restoreUploadedSteps(
              storedSteps: null, storedDate: '2026-10-07', today: '2026-10-07'),
          0);
    });
  });

  group('stepUploadDelta', () {
    test('重開 App 還原後只送新增量', () {
      final last = restoreUploadedSteps(
          storedSteps: 5000, storedDate: '2026-10-07', today: '2026-10-07');
      expect(stepUploadDelta(fusedSteps: 5120, lastUploaded: last), 120);
    });
    test('融合步數未超過或回退時為 0', () {
      expect(stepUploadDelta(fusedSteps: 5000, lastUploaded: 5000), 0);
      expect(stepUploadDelta(fusedSteps: 4000, lastUploaded: 5000), 0);
    });
  });
}
