// ★ 2026-11 代理人協調：TaskDraft 解析、已看過過濾、建立回應解析。
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/screens/family/family_task_draft.dart';
import 'package:flutter_application_1/services/api/agent_task_api.dart';

Map<String, dynamic> _task(String id, String status, {DateTime? at, String? result}) => {
      'task_id': id,
      'status': status,
      'question': '愛吃什麼',
      'result_text': result ?? '',
      'answered_at': (at ?? DateTime.now().toUtc()).toIso8601String(),
    };

void main() {
  group('TaskDraft.tryParse', () {
    test('缺席、null、空問題回 null', () {
      expect(TaskDraft.tryParse(null), isNull);
      expect(TaskDraft.tryParse('x'), isNull);
      expect(TaskDraft.tryParse({'question': '  '}), isNull);
    });
    test('正常解析；未知 followup 退回 report', () {
      final d = TaskDraft.tryParse(
          {'question': ' 愛吃什麼 ', 'purpose': '訂餐', 'followup': 'schedule'})!;
      expect(d.question, '愛吃什麼');
      expect(d.followup, 'schedule');
      expect(TaskDraft.tryParse({'question': 'a', 'followup': 'zzz'})!.followup, 'report');
      expect(TaskDraft.tryParse({'question': 'a'})!.purpose, '');
    });
  });

  test('canSendTask 與 followup 標籤', () {
    expect(canSendTask(question: 'a', sending: true), isFalse);
    expect(canSendTask(question: ' ', sending: false), isFalse);
    expect(canSendTask(question: 'a', sending: false), isTrue);
    expect(taskFollowupLabel('schedule'), '問到後幫您排提醒');
    expect(taskFollowupLabel('report'), '問到後回報給您');
  });

  group('selectUnseenTasks', () {
    test('只留 answered/expired、未看過、7 天內，並改舊→新', () {
      final tasks = [
        _task('3', 'answered'),
        _task('2', 'pending'),
        _task('1', 'expired'),
        _task('0', 'answered', at: DateTime.now().toUtc().subtract(const Duration(days: 10))),
        _task('9', 'asked'),
      ];
      final out = selectUnseenTasks(tasks, {'3'});
      expect(out.map((t) => t['task_id']).toList(), ['1']);
      final all = selectUnseenTasks(tasks, {});
      expect(all.map((t) => t['task_id']).toList(), ['1', '3']);
    });
    test('時間解析不到就略過', () {
      expect(selectUnseenTasks([{'task_id': '1', 'status': 'answered'}], {}), isEmpty);
    });
  });

  test('taskResultText', () {
    expect(taskResultText('阿嬤', _task('1', 'answered', result: '她愛吃魚')), '她愛吃魚');
    expect(taskResultText('阿嬤', _task('1', 'expired')), contains('還沒問到'));
  });

  group('AgentTaskApi.parseCreateResponse', () {
    test('成功用 reply_text，缺席用預設', () {
      final ok = AgentTaskApi.parseCreateResponse(
          {'success': true, 'data': {'task_id': 5, 'reply_text': '好的'}});
      expect(ok.ok, isTrue);
      expect(ok.message, '好的');
      expect(AgentTaskApi.parseCreateResponse({'success': true, 'data': {}}).message,
          AgentTaskApi.defaultSentMessage);
    });
    test('404/409 顯示 detail，null 為網路錯誤', () {
      final r = AgentTaskApi.parseCreateResponse({'detail': '待辦太多了'});
      expect(r.ok, isFalse);
      expect(r.message, '待辦太多了');
      expect(AgentTaskApi.parseCreateResponse({}).ok, isFalse);
      expect(AgentTaskApi.parseCreateResponse(null).message, AgentTaskApi.networkErrorMessage);
    });
  });
}
