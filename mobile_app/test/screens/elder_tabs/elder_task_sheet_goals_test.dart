import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/elder_tabs/widgets/elder_task_sheet.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/reminder_schedule.dart';

Map<String, dynamic> r(int id, String title, {bool elder = false}) => {
      'id': id,
      'title': title,
      'time_str': '08:0$id',
      'category': 'custom',
      'created_by_role': elder ? 'elder' : 'family',
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('分成「家人提醒」「我的目標」兩區，總數含兩者，並有新增按鈕', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var added = 0;
    final groups = ReminderGroups(
      dueNow: [r(1, '吃藥'), r(2, '散步', elder: true)],
      later: const [],
      done: [r(3, '喝水', elder: true)],
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Theme(
          data: buildAppTheme(context),
          child: Scaffold(
            body: SingleChildScrollView(
              child: ElderTaskSheetBody(
                readGroups: () => groups,
                onCheckIn: (_) async {},
                onAddGoal: () async => added++,
                onEditGoal: (_) async {},
                onDeleteGoal: (_) async {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('家人提醒'), findsOneWidget);
    expect(find.text('我的目標'), findsOneWidget);
    expect(find.text('1／3'), findsOneWidget);
    expect(find.text('吃藥'), findsOneWidget);
    expect(find.text('散步'), findsOneWidget);
    expect(find.text('喝水'), findsOneWidget);
    expect(find.byTooltip('修改或刪除 散步'), findsOneWidget);
    expect(find.byTooltip('修改或刪除 吃藥'), findsNothing, reason: '家人提醒不可編輯');

    await tester.tap(find.text('新增我的目標'));
    await tester.pump();
    expect(added, 1);
  });
}
