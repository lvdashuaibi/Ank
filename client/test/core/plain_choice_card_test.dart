import 'package:flashcard_app/core/plain_choice_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses AI generated single choice text into selectable options', () {
    final PlainChoiceQuestion? question = PlainChoiceQuestion.tryParse(
      prompt: '''
根据文本，形成性评估的主要作用是什么？
A. 定义学习者发展
B. 支持及时反馈
C. 确定课程目标
D. 提供最终等级
''',
      answer: 'B. 支持及时反馈',
    );

    expect(question, isNotNull);
    expect(question!.isMultiSelect, isFalse);
    expect(question.stem, '根据文本，形成性评估的主要作用是什么？');
    expect(
      question.options.map((PlainChoiceOption option) => option.label),
      <String>['A. 定义学习者发展', 'B. 支持及时反馈', 'C. 确定课程目标', 'D. 提供最终等级'],
    );
    expect(question.correctIds, <String>{'B'});
  });

  test('parses multi choice answers with repeated letter labels', () {
    final PlainChoiceQuestion? question = PlainChoiceQuestion.tryParse(
      prompt: '''
教育目的制约哪些方面？（多选）
A. 课程
B. 教学
C. 评价
D. 学校建筑风格
E. 教师工资
''',
      answer: 'A. 课程, B. 教学, C. 评价',
    );

    expect(question, isNotNull);
    expect(question!.isMultiSelect, isTrue);
    expect(question.correctIds, <String>{'A', 'B', 'C'});
    expect(question.isCorrect(<String>{'A', 'B', 'C'}), isTrue);
    expect(question.isCorrect(<String>{'A', 'C'}), isFalse);
  });
}
