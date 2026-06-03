import 'package:flutter_test/flutter_test.dart';

import 'package:flashcard_app/core/app_store.dart';

void main() {
  test('AI generated card parses quality report', () {
    final AIGeneratedCard card = AIGeneratedCard.fromJson(<String, dynamic>{
      'title': '教育目的',
      'content': '教育目的是什么？\n\n@answer\n培养人的质量规格。\n@end',
      'tags': <String>['AI生成'],
      'note': '',
      'quality_report': <String, dynamic>{
        'score': 0.78,
        'badges': <String>['需要检查'],
        'repairable': true,
        'violations': <Map<String, dynamic>>[
          <String, dynamic>{
            'code': 'answer_too_long',
            'message': '答案过长',
            'severity': 'warning',
          },
        ],
      },
    });

    expect(card.qualityReport?.score, 0.78);
    expect(card.qualityReport?.repairable, isTrue);
    expect(card.qualityReport?.violations.single.code, 'answer_too_long');
  });

  test('AI generated card can apply rewrite candidate before saving', () {
    const AIGeneratedCard original = AIGeneratedCard(
      title: '教育目的',
      content: '教育目的是什么？\n\n@answer\n培养人的质量规格。\n@end',
      tags: <String>['AI生成', '教育学'],
      note: '原始备注',
      sourceLocation: '第一章',
      qualityReport: AIQualityReport(
        score: 1,
        badges: <String>['规则通过'],
        violations: <AIQualityViolation>[],
        repairable: false,
      ),
    );

    final AIGeneratedCard updated = original.applyRewrite(
      const AIRewriteCandidate(
        title: '教育目的的含义',
        content: '教育目的指什么？\n\n@answer\n预期培养人的质量规格。\n@end',
        changeSummary: '压缩答案',
        qualityNotes: <String>['更短'],
      ),
    );

    expect(updated.title, '教育目的的含义');
    expect(updated.content, contains('预期培养人的质量规格'));
    expect(updated.tags, original.tags);
    expect(updated.note, original.note);
    expect(updated.sourceLocation, '第一章');
    expect(updated.qualityReport, isNull);
  });

  test('generation policy serializes to API shape', () {
    const GenerationPolicy policy = GenerationPolicy(
      name: '教育学精读',
      atomicityLevel: 'strict',
      answerStyle: 'one_sentence',
      maxAnswerChars: 40,
      preferredCardTypes: <String>['basic', 'cloze'],
      splitStrategy: 'by_heading',
      coverageMode: 'balanced',
      repairMode: 'violations_only',
      customRules: '避免宽泛论述题',
    );

    final Map<String, dynamic> json = policy.toJson();

    expect(json['name'], '教育学精读');
    expect(json['max_answer_chars'], 40);
    expect(json['preferred_card_types'], <String>['basic', 'cloze']);
    expect(json['custom_rules'], '避免宽泛论述题');
  });

  test('generation policy uses default card types when API omits them', () {
    final GenerationPolicy policy = GenerationPolicy.fromJson(<String, dynamic>{
      'name': '教育学精读',
    });

    expect(policy.preferredCardTypes, <String>['basic', 'cloze']);
  });

  test('AI document summary parses imported image metadata', () {
    final AIDocumentSummary summary = AIDocumentSummary.fromJson(
      <String, dynamic>{
        'title': 'education.md',
        'mime_type': 'text/markdown',
        'text_preview': '[图片: 教育目的结构图]',
        'text_length': 42,
        'chunk_count': 2,
        'image_count': 1,
        'images': <Map<String, dynamic>>[
          <String, dynamic>{
            'alt': '教育目的结构图',
            'source': 'images/aims.png',
            'is_remote': false,
          },
        ],
      },
    );

    expect(summary.imageCount, 1);
    expect(summary.images.single.alt, '教育目的结构图');
    expect(summary.images.single.source, 'images/aims.png');
    expect(summary.images.single.isRemote, isFalse);
  });

  test('AI generation job parses recoverable draft result', () {
    final AIGenerationJob job = AIGenerationJob.fromJson(<String, dynamic>{
      'id': 'job-1',
      'source_name': 'education.md',
      'source_type': 'text/markdown',
      'status': 'succeeded',
      'progress': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'result': <String, dynamic>{
        'document': <String, dynamic>{
          'title': 'education.md',
          'mime_type': 'text/markdown',
          'text_preview': '教育目的',
          'text_length': 4,
        },
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': '教育目的',
            'content': '教育目的是什么？\n\n@answer\n培养人的质量规格。\n@end',
            'tags': <String>['AI生成'],
            'note': '',
          },
        ],
      },
    });

    expect(job.hasResult, isTrue);
    expect(job.document?.title, 'education.md');
    expect(job.resultItems.single.title, '教育目的');
  });

  test('copyWith can clear generated document summary', () {
    final AppState state = AppState(
      decks: const <DeckModel>[],
      cards: const <CardModel>[],
      completedToday: 0,
      reviewedReviewTodayByDeck: const <String, int>{},
      introducedNewTodayByDeck: const <String, int>{},
      isBootstrapping: false,
      syncInProgress: false,
      pendingOperations: const <SyncOperation>[],
      generatedCards: const <AIGeneratedCard>[],
      generatedDocument: const AIDocumentSummary(
        title: 'notes.pdf',
        mimeType: 'application/pdf',
        textPreview: 'preview',
        textLength: 7,
      ),
    );

    final AppState next = state.copyWith(clearGeneratedDocument: true);

    expect(next.generatedDocument, isNull);
  });
}
