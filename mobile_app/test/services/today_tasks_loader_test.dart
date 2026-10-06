// TodayTasksLoader 合併邏輯：本機完成集 ∪ 後端 completed_ids。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/today_tasks_loader.dart';

void main() {
  group('mergeCompleted', () {
    test('聯集：保留本機獨有 id（可能離線未送出），加入後端 id', () {
      expect(TodayTasksLoader.mergeCompleted({1, 2}, [2, 3]), {1, 2, 3});
    });

    test('後端欄位缺失或型別不對：只用本機', () {
      expect(TodayTasksLoader.mergeCompleted({1}, null), {1});
      expect(TodayTasksLoader.mergeCompleted({1}, 'oops'), {1});
    });

    test('後端 id 為字串也能解析、無法解析者略過', () {
      expect(TodayTasksLoader.mergeCompleted({}, ['5', 'x', 6]), {5, 6});
    });
  });
}
