import 'package:flashcard_app/app/card_dsl/dsl_ast.dart';
import 'package:flashcard_app/app/card_dsl/dsl_parser.dart';
import 'package:flashcard_app/app/card_dsl/dsl_plaintext.dart';
import 'package:flashcard_app/app/card_dsl/dsl_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String singleChoiceDsl = '''{single-choice}
Q: TCP 是哪种协议？
* 面向连接
- 无连接
{/single-choice}''';
  const String multiChoiceDsl = '''{multi-choice}
Q: 哪些属于传输层协议？
* TCP
* UDP
- HTTP
{/multi-choice}''';

  test('DslParser parses custom single-choice block for review', () {
    final DslParseResult result = DslParser.parseBlocks(singleChoiceDsl);

    expect(result.errors, isEmpty);
    expect(result.blocks, hasLength(2));

    final DslParagraphNode questionBlock =
        result.blocks.first as DslParagraphNode;
    expect(_plain(questionBlock.lines.first), 'TCP 是哪种协议？');

    final DslChoiceGroupNode choiceBlock =
        result.blocks[1] as DslChoiceGroupNode;
    expect(choiceBlock.multiSelect, isFalse);
    expect(choiceBlock.options, hasLength(2));
    expect(choiceBlock.options[0].isCorrect, isTrue);
    expect(_plain(choiceBlock.options[0].content), '面向连接');
    expect(choiceBlock.options[1].isCorrect, isFalse);
    expect(_plain(choiceBlock.options[1].content), '无连接');
  });

  test('dslToPlainText strips custom single-choice markers', () {
    expect(dslToPlainText(singleChoiceDsl), 'TCP 是哪种协议？ 面向连接 无连接');
  });

  test('DslParser parses custom multi-choice block for review', () {
    final DslParseResult result = DslParser.parseBlocks(multiChoiceDsl);

    expect(result.errors, isEmpty);
    expect(result.blocks, hasLength(2));

    final DslParagraphNode questionBlock =
        result.blocks.first as DslParagraphNode;
    expect(_plain(questionBlock.lines.first), '哪些属于传输层协议？');

    final DslChoiceGroupNode choiceBlock =
        result.blocks[1] as DslChoiceGroupNode;
    expect(choiceBlock.multiSelect, isTrue);
    expect(choiceBlock.options, hasLength(3));
    expect(choiceBlock.options[0].isCorrect, isTrue);
    expect(choiceBlock.options[1].isCorrect, isTrue);
    expect(choiceBlock.options[2].isCorrect, isFalse);
  });

  test('dslToPlainText strips custom multi-choice markers', () {
    expect(dslToPlainText(multiChoiceDsl), '哪些属于传输层协议？ TCP UDP HTTP');
  });

  testWidgets('DslCardView renders custom single-choice block in review', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DslCardView(
            front: singleChoiceDsl,
            back: '',
            revealed: false,
            onReveal: _noop,
          ),
        ),
      ),
    );

    expect(find.text('TCP 是哪种协议？', findRichText: true), findsOneWidget);
    expect(find.text('面向连接'), findsOneWidget);
    expect(find.text('无连接'), findsOneWidget);
    expect(find.text('提交答案'), findsOneWidget);

    await tester.tap(find.text('提交答案'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
  });

  testWidgets('DslCardView renders custom multi-choice block in review', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DslCardView(
            front: multiChoiceDsl,
            back: '',
            revealed: false,
            onReveal: _noop,
          ),
        ),
      ),
    );

    expect(find.text('哪些属于传输层协议？', findRichText: true), findsOneWidget);
    expect(find.text('TCP'), findsOneWidget);
    expect(find.text('UDP'), findsOneWidget);
    expect(find.text('HTTP'), findsOneWidget);
    expect(find.text('提交答案'), findsOneWidget);

    await tester.tap(find.text('提交答案'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
  });
}

void _noop() {}

String _plain(List<DslInlineNode> nodes) {
  final StringBuffer buffer = StringBuffer();
  for (final DslInlineNode node in nodes) {
    if (node is DslTextNode) {
      buffer.write(node.text);
    }
  }
  return buffer.toString();
}
