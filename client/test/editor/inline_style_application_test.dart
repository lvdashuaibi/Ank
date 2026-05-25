import 'package:flashcard_app/app/editor/models.dart';
import 'package:flashcard_app/app/editor/rich_text_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applyInlineStyleToRange adds highlight span', () {
    final List<InlineStyleSpan> spans = applyInlineStyleToRange(
      spans: const <InlineStyleSpan>[],
      start: 2,
      end: 6,
      style: InlineStyle.highlight,
    );

    expect(spans, hasLength(1));
    expect(spans.first.start, 2);
    expect(spans.first.end, 6);
    expect(spans.first.style, InlineStyle.highlight);
  });

  test('applyInlineStyleToRange toggles same style off', () {
    final List<InlineStyleSpan> spans = applyInlineStyleToRange(
      spans: const <InlineStyleSpan>[
        InlineStyleSpan(start: 0, end: 4, style: InlineStyle.highlight),
      ],
      start: 0,
      end: 4,
      style: InlineStyle.highlight,
    );

    expect(spans, isEmpty);
  });

  test('applyInlineStyleToRange replaces fontLarge with fontSmall', () {
    final List<InlineStyleSpan> spans = applyInlineStyleToRange(
      spans: const <InlineStyleSpan>[
        InlineStyleSpan(start: 0, end: 4, style: InlineStyle.fontLarge),
      ],
      start: 0,
      end: 4,
      style: InlineStyle.fontSmall,
    );

    expect(spans, hasLength(1));
    expect(spans.first.start, 0);
    expect(spans.first.end, 4);
    expect(spans.first.style, InlineStyle.fontSmall);
  });

  test('applyInlineStyleToRange replaces fontSmall with fontLarge', () {
    final List<InlineStyleSpan> spans = applyInlineStyleToRange(
      spans: const <InlineStyleSpan>[
        InlineStyleSpan(start: 0, end: 4, style: InlineStyle.fontSmall),
      ],
      start: 0,
      end: 4,
      style: InlineStyle.fontLarge,
    );

    expect(spans, hasLength(1));
    expect(spans.first.start, 0);
    expect(spans.first.end, 4);
    expect(spans.first.style, InlineStyle.fontLarge);
  });

  test('applyInlineStyleToRange splits conflicting font span around range', () {
    final List<InlineStyleSpan> spans = applyInlineStyleToRange(
      spans: const <InlineStyleSpan>[
        InlineStyleSpan(start: 0, end: 10, style: InlineStyle.fontLarge),
        InlineStyleSpan(start: 0, end: 10, style: InlineStyle.bold),
      ],
      start: 3,
      end: 7,
      style: InlineStyle.fontSmall,
    );

    expect(spans, hasLength(4));
    expect(spans[0].style, InlineStyle.fontLarge);
    expect(spans[0].start, 0);
    expect(spans[0].end, 3);
    expect(spans[1].style, InlineStyle.fontLarge);
    expect(spans[1].start, 7);
    expect(spans[1].end, 10);
    expect(spans[2].style, InlineStyle.bold);
    expect(spans[2].start, 0);
    expect(spans[2].end, 10);
    expect(spans[3].style, InlineStyle.fontSmall);
    expect(spans[3].start, 3);
    expect(spans[3].end, 7);
  });
}
