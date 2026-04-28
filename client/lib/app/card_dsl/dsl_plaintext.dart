String dslToPlainText(String input) {
  var text = input;
  text = text.replaceAll('{single-choice}', '');
  text = text.replaceAll('{/single-choice}', '');
  text = text.replaceAll('{multi-choice}', '');
  text = text.replaceAll('{/multi-choice}', '');
  text = text.replaceAll(RegExp(r'^\s*Q[:：]\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*[*-]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'\{\{[^}]+\}\}'), '____');
  text = text.replaceAll(RegExp(r'___\([^)]*\)___'), '____');
  text = text.replaceAll(RegExp(r'_{3,}'), '____');
  text = text.replaceAll(
    RegExp(r'^\s*[\(\[]\s*[x ]\s*[\)\]]\s+', multiLine: true),
    '',
  );
  text = text.replaceAll(RegExp(r'^\s*\{[TF]\}\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'\{(hint|explain):[^}]*\}'), '');
  text = text.replaceAll('{/hint}', '');
  text = text.replaceAll('{/explain}', '');
  text = text.replaceAll(RegExp(r'\{(red|blue|green|orange|purple|gray):'), '');
  text = text.replaceAll(RegExp(r'\{bg:[^:}]+:'), '');
  text = text.replaceAll(RegExp(r'\{(u|sup|sub|kbd):'), '');
  text = text.replaceAll(RegExp(r'\{size:[^:}]+:'), '');
  text = text.replaceAll('}', '');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}
