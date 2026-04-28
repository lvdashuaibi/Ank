import 'package:flashcard_app/core/import/card_dsl_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wrapped @card block supports @answer as main format', () {
    const String input = '''
@card
#deck: 计算机网络
#tags: tcp, basics
TCP 的三次握手分别是什么？

@answer
SYN -> SYN/ACK -> ACK
@end
---meta---
来源：谢希仁《计算机网络》
@end
''';

    final CardDslParseResult result = CardDslParser.parseDocument(input);

    expect(result.errors, isEmpty);
    expect(result.cards, hasLength(1));
    expect(result.cards.single.front, 'TCP 的三次握手分别是什么？');
    expect(result.cards.single.back, 'SYN -> SYN/ACK -> ACK');
    expect(result.cards.single.note, '来源：谢希仁《计算机网络》');
  });

  test('supports simplified single-card input with @answer', () {
    const String input = '''
#deck: 英语
#tags: vocabulary，travel、speaking;review；oral
#type: phrase

How do you say "机场" in English?

@answer
airport
@end
''';

    final CardDslParseResult result = CardDslParser.parseDocument(input);

    expect(result.errors, isEmpty);
    expect(result.cards, hasLength(1));
    expect(result.cards.single.deckName, '英语');
    expect(
      result.cards.single.tags,
      containsAll(<String>[
        'vocabulary',
        'travel',
        'speaking',
        'review',
        'oral',
        'phrase',
        'dsl',
      ]),
    );
    expect(result.cards.single.front, 'How do you say "机场" in English?');
    expect(result.cards.single.back, 'airport');
  });

  test(
    'supports simplified multi-card input separated by === with @answer',
    () {
      const String input = '''
#deck: 英语
Question 1

@answer
Answer 1
@end

===

#deck: 计算机网络
Question 2

@answer
Answer 2
@end
''';

      final CardDslParseResult result = CardDslParser.parseDocument(input);

      expect(result.errors, isEmpty);
      expect(result.cards, hasLength(2));
      expect(result.cards[0].deckName, '英语');
      expect(result.cards[0].front, 'Question 1');
      expect(result.cards[0].back, 'Answer 1');
      expect(result.cards[1].deckName, '计算机网络');
      expect(result.cards[1].front, 'Question 2');
      expect(result.cards[1].back, 'Answer 2');
    },
  );

  test('legacy ---front---/---back--- format remains compatible', () {
    const String input = '''
@card
#deck: 计算机网络
---front---
TCP 属于哪类协议？
---back---
面向连接
@end
''';

    final CardDslParseResult result = CardDslParser.parseDocument(input);

    expect(result.errors, isEmpty);
    expect(result.cards, hasLength(1));
    expect(result.cards.single.front, 'TCP 属于哪类协议？');
    expect(result.cards.single.back, '面向连接');
  });

  test('missing @end for @answer is tolerated and reported', () {
    const String input = '''
#deck: 计算机网络

TCP 属于哪类协议？

@answer
面向连接
''';

    final CardDslParseResult result = CardDslParser.parseDocument(input);

    expect(result.cards, hasLength(1));
    expect(result.cards.single.front, 'TCP 属于哪类协议？');
    expect(result.cards.single.back, '面向连接');
    expect(
      result.errors,
      contains('Card#1: missing @end for @answer，已在文档结尾自动结束'),
    );
  });

  test('plain text without section markers falls back to front content', () {
    const String input = '''
HTTP 默认端口是 80。
HTTPS 默认端口是 443。
''';

    final CardDslParseResult result = CardDslParser.parseDocument(input);

    expect(result.errors, isEmpty);
    expect(result.cards, hasLength(1));
    expect(result.cards.single.front, 'HTTP 默认端口是 80。\nHTTPS 默认端口是 443。');
    expect(result.cards.single.back, isEmpty);
  });
}
