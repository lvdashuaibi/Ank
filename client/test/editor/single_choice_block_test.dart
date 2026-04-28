import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/app/editor/single_choice_block.dart';

void main() {
  testWidgets('single choice block supports edit and answer flow', (
    WidgetTester tester,
  ) async {
    SingleChoiceBlockData? latestData;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChoiceBlockCard(
            data: const SingleChoiceBlockData(
              question: 'TCP 属于哪类协议？',
              options: <String>['面向连接', '无连接'],
              correctIndex: 0,
            ),
            onChanged: (SingleChoiceBlockData data) {
              latestData = data;
            },
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('单选题'), findsOneWidget);
    expect(find.widgetWithText(TextField, '题干'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '题干'), 'UDP 属于哪类协议？');
    await tester.pump();

    expect(latestData?.question, 'UDP 属于哪类协议？');

    await tester.tap(find.text('作答'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('无连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交答案'));
    await tester.pumpAndSettle();

    expect(find.text('回答错误，正确答案：A. 面向连接'), findsOneWidget);

    await tester.tap(find.text('重新作答'));
    await tester.pumpAndSettle();
    expect(find.text('回答错误，正确答案：A. 面向连接'), findsNothing);
  });

  testWidgets('multi choice block supports edit and answer flow', (
    WidgetTester tester,
  ) async {
    MultiChoiceBlockData? latestData;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiChoiceBlockCard(
            data: const MultiChoiceBlockData(
              question: '哪些属于传输层协议？',
              options: <String>['TCP', 'UDP', 'HTTP'],
              correctIndexes: <int>[0, 1],
            ),
            onChanged: (MultiChoiceBlockData data) {
              latestData = data;
            },
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('多选题'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '题干'), '哪些属于网络层协议？');
    await tester.pump();

    expect(latestData?.question, '哪些属于网络层协议？');

    await tester.tap(find.text('作答'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('TCP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTTP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交答案'));
    await tester.pumpAndSettle();

    expect(find.text('回答错误，正确答案：A. TCP；B. UDP'), findsOneWidget);

    await tester.tap(find.text('重新作答'));
    await tester.pumpAndSettle();
    expect(find.text('回答错误，正确答案：A. TCP；B. UDP'), findsNothing);
  });
}
