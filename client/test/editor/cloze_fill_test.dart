import 'package:flashcard_app/app/card_dsl/dsl_view.dart';
import 'package:flashcard_app/app/editor/document_codec.dart';
import 'package:flashcard_app/app/editor/models.dart';
import 'package:flashcard_app/app/editor/rich_text_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transformInlineMarkdown parses cloze span', () {
    final EditorRichText richText = transformInlineMarkdown(
      raw: 'HTTP 默认端口是 {{80}}。',
      caretOffset: 'HTTP 默认端口是 {{80}}。'.length,
    );

    expect(richText.text, 'HTTP 默认端口是 80。');
    expect(richText.spans, hasLength(1));
    expect(richText.spans.first.style, InlineStyle.cloze);
    expect(richText.spans.first.start, 11);
    expect(richText.spans.first.end, 13);
  });

  test('encodeSingleRichText encodes cloze span to DSL', () {
    final String encoded = EditorDocumentCodec.encodeSingleRichText(
      const EditorRichText(
        text: 'HTTP 默认端口是 80。',
        spans: <InlineStyleSpan>[
          InlineStyleSpan(start: 11, end: 13, style: InlineStyle.cloze),
        ],
      ),
    );

    expect(encoded, 'HTTP 默认端口是 {{80}}。');
  });

  testWidgets('DslCardView reveals cloze answer after tapping blank', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DslCardView(
            front: 'HTTP 默认端口是 {{80}}。',
            back: '',
            revealed: false,
          ),
        ),
      ),
    );

    expect(find.text('80'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('dsl_cloze_blank')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('dsl_cloze_blank')));
    await tester.pumpAndSettle();

    expect(find.text('80'), findsOneWidget);
  });

  testWidgets('cloze blank keeps roughly the selected text width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DslCardView(front: '今天学 {{钙}}。', back: '', revealed: false),
        ),
      ),
    );

    final Size blankSize = tester.getSize(
      find.byKey(const ValueKey<String>('dsl_cloze_blank')),
    );

    expect(blankSize.width, lessThan(44));
    expect(blankSize.width, greaterThanOrEqualTo(16));
  });
}
