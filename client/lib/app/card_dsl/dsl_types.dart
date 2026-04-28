enum DslBlockType {
  paragraph,
  singleChoice,
  multiChoice,
  trueFalse,
  answerLines,
  hint,
  explain,
  unknown,
}

class DslBlock {
  const DslBlock({
    required this.type,
    required this.text,
    this.items = const <DslItem>[],
    this.expected = const <String>[],
    this.title,
  });

  final DslBlockType type;
  final String text;
  final List<DslItem> items;
  final List<String> expected;
  final String? title;
}

class DslItem {
  const DslItem({
    required this.text,
    required this.correct,
  });

  final String text;
  final bool correct;
}

