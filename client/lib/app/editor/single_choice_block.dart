import 'package:flutter/material.dart';

@immutable
class SingleChoiceBlockData {
  const SingleChoiceBlockData({
    required this.question,
    required this.options,
    required this.correctIndex,
  });

  final String question;
  final List<String> options;
  final int correctIndex;

  SingleChoiceBlockData copyWith({
    String? question,
    List<String>? options,
    int? correctIndex,
  }) {
    return SingleChoiceBlockData(
      question: question ?? this.question,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
    );
  }

  SingleChoiceBlockData normalized() {
    final List<String> normalizedOptions = List<String>.from(options);
    while (normalizedOptions.length < 2) {
      normalizedOptions.add('');
    }
    final int safeCorrectIndex = correctIndex.clamp(
      0,
      normalizedOptions.length - 1,
    );
    return SingleChoiceBlockData(
      question: question,
      options: normalizedOptions,
      correctIndex: safeCorrectIndex,
    );
  }
}

@immutable
class MultiChoiceBlockData {
  const MultiChoiceBlockData({
    required this.question,
    required this.options,
    required this.correctIndexes,
  });

  final String question;
  final List<String> options;
  final List<int> correctIndexes;

  MultiChoiceBlockData copyWith({
    String? question,
    List<String>? options,
    List<int>? correctIndexes,
  }) {
    return MultiChoiceBlockData(
      question: question ?? this.question,
      options: options ?? this.options,
      correctIndexes: correctIndexes ?? this.correctIndexes,
    );
  }

  MultiChoiceBlockData normalized() {
    final List<String> normalizedOptions = List<String>.from(options);
    while (normalizedOptions.length < 2) {
      normalizedOptions.add('');
    }
    final Set<int> safeCorrectIndexSet = correctIndexes
        .where((int index) => index >= 0 && index < normalizedOptions.length)
        .toSet();
    if (safeCorrectIndexSet.isEmpty) {
      safeCorrectIndexSet.add(0);
    }
    final List<int> safeCorrectIndexes = safeCorrectIndexSet.toList()..sort();
    return MultiChoiceBlockData(
      question: question,
      options: normalizedOptions,
      correctIndexes: safeCorrectIndexes,
    );
  }
}

enum SingleChoiceBlockMode { edit, answer }

enum MultiChoiceBlockMode { edit, answer }

class SingleChoiceBlockCard extends StatefulWidget {
  const SingleChoiceBlockCard({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onDelete,
    this.autofocusQuestion = false,
    this.embedded = false,
  });

  final SingleChoiceBlockData data;
  final ValueChanged<SingleChoiceBlockData> onChanged;
  final VoidCallback onDelete;
  final bool autofocusQuestion;
  final bool embedded;

  @override
  State<SingleChoiceBlockCard> createState() => _SingleChoiceBlockCardState();
}

class _SingleChoiceBlockCardState extends State<SingleChoiceBlockCard> {
  late final TextEditingController _questionController;
  final List<TextEditingController> _optionControllers =
      <TextEditingController>[];
  late final FocusNode _questionFocusNode;
  late SingleChoiceBlockMode _mode;
  late int _correctIndex;
  int? _selectedIndex;
  bool _submitted = false;
  bool _autofocusHandled = false;

  @override
  void initState() {
    super.initState();
    final SingleChoiceBlockData normalized = widget.data.normalized();
    _questionController = TextEditingController(text: normalized.question);
    _questionFocusNode = FocusNode();
    _correctIndex = normalized.correctIndex;
    _mode = SingleChoiceBlockMode.edit;
    _syncOptionControllers(normalized.options);
    _scheduleAutofocusIfNeeded();
  }

  @override
  void didUpdateWidget(covariant SingleChoiceBlockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final SingleChoiceBlockData normalized = widget.data.normalized();
    if (_questionController.text != normalized.question) {
      _questionController.text = normalized.question;
    }
    if (_correctIndex != normalized.correctIndex) {
      _correctIndex = normalized.correctIndex;
    }
    final bool optionsChanged =
        normalized.options.length != _optionControllers.length ||
        !_listEquals(
          normalized.options,
          _optionControllers.map((TextEditingController c) => c.text).toList(),
        );
    if (optionsChanged) {
      _syncOptionControllers(normalized.options);
    }
    _scheduleAutofocusIfNeeded();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _questionFocusNode.dispose();
    for (final TextEditingController controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool editOnly = widget.embedded;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.embedded ? 6 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (widget.embedded) ...<Widget>[
                Icon(
                  Icons.radio_button_checked_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '单选题',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '单选题',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              if (!editOnly) ...<Widget>[
                const SizedBox(width: 8),
                _ModeChip(
                  label: '编辑',
                  selected: _mode == SingleChoiceBlockMode.edit,
                  onTap: () => _switchMode(SingleChoiceBlockMode.edit),
                ),
                const SizedBox(width: 6),
                _ModeChip(
                  label: '作答',
                  selected: _mode == SingleChoiceBlockMode.answer,
                  onTap: () => _switchMode(SingleChoiceBlockMode.answer),
                ),
              ],
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '删除单选题',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (editOnly || _mode == SingleChoiceBlockMode.edit)
            _buildEditMode(context)
          else
            _buildAnswerMode(context),
        ],
      ),
    );
  }

  Widget _buildEditMode(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _questionController,
          focusNode: _questionFocusNode,
          onChanged: (_) => _emitChanged(),
          maxLines: 2,
          minLines: 1,
          decoration: _embeddedFieldDecoration(
            context,
            isDense: true,
            labelText: '题干',
            hintText: '例如：TCP 属于哪类协议？',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '选项（点击左侧圆圈设置正确答案）',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (int index = 0; index < _optionControllers.length; index += 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '设为正确答案',
                  onPressed: () {
                    setState(() {
                      _correctIndex = index;
                    });
                    _emitChanged();
                  },
                  icon: Icon(
                    index == _correctIndex
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: index == _correctIndex
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
                Container(
                  width: 28,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _optionLabel(index),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _optionControllers[index],
                    onChanged: (_) => _emitChanged(),
                    maxLines: 1,
                    decoration: _embeddedFieldDecoration(
                      context,
                      isDense: true,
                      hintText: '选项 ${_optionLabel(index)}',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '删除选项',
                  onPressed: _optionControllers.length <= 2
                      ? null
                      : () => _removeOption(index),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: _addOption,
          icon: const Icon(Icons.add),
          label: const Text('新增选项'),
        ),
      ],
    );
  }

  Widget _buildAnswerMode(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String question = _questionController.text.trim().isEmpty
        ? '（未填写题干）'
        : _questionController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          question,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (int index = 0; index < _optionControllers.length; index += 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AnswerOptionTile(
              label: _optionLabel(index),
              text: _optionControllers[index].text.trim().isEmpty
                  ? '（空选项）'
                  : _optionControllers[index].text.trim(),
              selected: _selectedIndex == index,
              correct: _submitted && index == _correctIndex,
              wrong:
                  _submitted &&
                  _selectedIndex == index &&
                  _selectedIndex != _correctIndex,
              onTap: _submitted
                  ? null
                  : () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
            ),
          ),
        Row(
          children: <Widget>[
            FilledButton.tonal(
              onPressed: _selectedIndex == null ? null : _submitAnswer,
              child: Text(_submitted ? '已判定' : '提交答案'),
            ),
            if (_submitted) ...<Widget>[
              const SizedBox(width: 8),
              TextButton(onPressed: _resetAnswering, child: const Text('重新作答')),
            ],
          ],
        ),
        if (_submitted) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (_selectedIndex == _correctIndex)
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _selectedIndex == _correctIndex
                  ? '回答正确'
                  : '回答错误，正确答案：${_optionLabel(_correctIndex)}. ${_optionControllers[_correctIndex].text.trim()}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: (_selectedIndex == _correctIndex)
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _switchMode(SingleChoiceBlockMode nextMode) {
    if (_mode == nextMode) {
      return;
    }
    setState(() {
      _mode = nextMode;
      _resetAnswerState();
    });
  }

  void _submitAnswer() {
    setState(() {
      _submitted = true;
    });
  }

  void _resetAnswering() {
    setState(_resetAnswerState);
  }

  void _resetAnswerState() {
    _selectedIndex = null;
    _submitted = false;
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
    _emitChanged();
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      return;
    }
    final TextEditingController controller = _optionControllers.removeAt(index);
    controller.dispose();
    setState(() {
      if (_correctIndex >= _optionControllers.length) {
        _correctIndex = _optionControllers.length - 1;
      } else if (index < _correctIndex) {
        _correctIndex -= 1;
      }
      if (_selectedIndex != null) {
        if (_selectedIndex == index) {
          _selectedIndex = null;
          _submitted = false;
        } else if (_selectedIndex! > index) {
          _selectedIndex = _selectedIndex! - 1;
        }
      }
    });
    _emitChanged();
  }

  void _emitChanged() {
    final List<String> options = _optionControllers
        .map((TextEditingController controller) => controller.text)
        .toList(growable: false);
    final SingleChoiceBlockData data = SingleChoiceBlockData(
      question: _questionController.text,
      options: options,
      correctIndex: _correctIndex.clamp(0, options.length - 1),
    ).normalized();
    widget.onChanged(data);
  }

  void _syncOptionControllers(List<String> options) {
    for (final TextEditingController controller in _optionControllers) {
      controller.dispose();
    }
    _optionControllers
      ..clear()
      ..addAll(
        options.map((String option) => TextEditingController(text: option)),
      );
  }

  void _scheduleAutofocusIfNeeded() {
    if (!widget.autofocusQuestion || _autofocusHandled) {
      return;
    }
    _autofocusHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _questionFocusNode.requestFocus();
      _questionController.selection = TextSelection.collapsed(
        offset: _questionController.text.length,
      );
    });
  }

  String _optionLabel(int index) {
    return String.fromCharCode(65 + index);
  }

  bool _listEquals(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

class MultiChoiceBlockCard extends StatefulWidget {
  const MultiChoiceBlockCard({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onDelete,
    this.autofocusQuestion = false,
    this.embedded = false,
  });

  final MultiChoiceBlockData data;
  final ValueChanged<MultiChoiceBlockData> onChanged;
  final VoidCallback onDelete;
  final bool autofocusQuestion;
  final bool embedded;

  @override
  State<MultiChoiceBlockCard> createState() => _MultiChoiceBlockCardState();
}

class _MultiChoiceBlockCardState extends State<MultiChoiceBlockCard> {
  late final TextEditingController _questionController;
  final List<TextEditingController> _optionControllers =
      <TextEditingController>[];
  late final FocusNode _questionFocusNode;
  late MultiChoiceBlockMode _mode;
  final Set<int> _correctIndexes = <int>{};
  final Set<int> _selectedIndexes = <int>{};
  bool _submitted = false;
  bool _autofocusHandled = false;

  @override
  void initState() {
    super.initState();
    final MultiChoiceBlockData normalized = widget.data.normalized();
    _questionController = TextEditingController(text: normalized.question);
    _questionFocusNode = FocusNode();
    _mode = MultiChoiceBlockMode.edit;
    _correctIndexes
      ..clear()
      ..addAll(normalized.correctIndexes);
    _syncOptionControllers(normalized.options);
    _scheduleAutofocusIfNeeded();
  }

  @override
  void didUpdateWidget(covariant MultiChoiceBlockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final MultiChoiceBlockData normalized = widget.data.normalized();
    if (_questionController.text != normalized.question) {
      _questionController.text = normalized.question;
    }
    if (!_intListEquals(
      normalized.correctIndexes,
      _correctIndexes.toList()..sort(),
    )) {
      _correctIndexes
        ..clear()
        ..addAll(normalized.correctIndexes);
    }
    final bool optionsChanged =
        normalized.options.length != _optionControllers.length ||
        !_stringListEquals(
          normalized.options,
          _optionControllers.map((TextEditingController c) => c.text).toList(),
        );
    if (optionsChanged) {
      _syncOptionControllers(normalized.options);
    }
    _scheduleAutofocusIfNeeded();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _questionFocusNode.dispose();
    for (final TextEditingController controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool editOnly = widget.embedded;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.embedded ? 6 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (widget.embedded) ...<Widget>[
                Icon(
                  Icons.check_box_outlined,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  '多选题',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '多选题',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              if (!editOnly) ...<Widget>[
                const SizedBox(width: 8),
                _ModeChip(
                  label: '编辑',
                  selected: _mode == MultiChoiceBlockMode.edit,
                  onTap: () => _switchMode(MultiChoiceBlockMode.edit),
                ),
                const SizedBox(width: 6),
                _ModeChip(
                  label: '作答',
                  selected: _mode == MultiChoiceBlockMode.answer,
                  onTap: () => _switchMode(MultiChoiceBlockMode.answer),
                ),
              ],
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '删除多选题',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (editOnly || _mode == MultiChoiceBlockMode.edit)
            _buildEditMode(context)
          else
            _buildAnswerMode(context),
        ],
      ),
    );
  }

  Widget _buildEditMode(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _questionController,
          focusNode: _questionFocusNode,
          onChanged: (_) => _emitChanged(),
          maxLines: 2,
          minLines: 1,
          decoration: _embeddedFieldDecoration(
            context,
            isDense: true,
            labelText: '题干',
            hintText: '例如：下面哪些属于 HTTP 特性？',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '选项（可勾选多个正确答案）',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (int index = 0; index < _optionControllers.length; index += 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '切换正确答案',
                  onPressed: () {
                    setState(() {
                      if (_correctIndexes.contains(index)) {
                        _correctIndexes.remove(index);
                      } else {
                        _correctIndexes.add(index);
                      }
                      if (_correctIndexes.isEmpty) {
                        _correctIndexes.add(index);
                      }
                    });
                    _emitChanged();
                  },
                  icon: Icon(
                    _correctIndexes.contains(index)
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: _correctIndexes.contains(index)
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
                Container(
                  width: 28,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _optionLabel(index),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _optionControllers[index],
                    onChanged: (_) => _emitChanged(),
                    maxLines: 1,
                    decoration: _embeddedFieldDecoration(
                      context,
                      isDense: true,
                      hintText: '选项 ${_optionLabel(index)}',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '删除选项',
                  onPressed: _optionControllers.length <= 2
                      ? null
                      : () => _removeOption(index),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: _addOption,
          icon: const Icon(Icons.add),
          label: const Text('新增选项'),
        ),
      ],
    );
  }

  Widget _buildAnswerMode(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String question = _questionController.text.trim().isEmpty
        ? '（未填写题干）'
        : _questionController.text.trim();
    final bool isCorrect = _setEquals(_selectedIndexes, _correctIndexes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          question,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '可多选',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        for (int index = 0; index < _optionControllers.length; index += 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AnswerOptionTile(
              label: _optionLabel(index),
              text: _optionControllers[index].text.trim().isEmpty
                  ? '（空选项）'
                  : _optionControllers[index].text.trim(),
              selected: _selectedIndexes.contains(index),
              correct: _submitted && _correctIndexes.contains(index),
              wrong:
                  _submitted &&
                  _selectedIndexes.contains(index) &&
                  !_correctIndexes.contains(index),
              onTap: _submitted
                  ? null
                  : () {
                      setState(() {
                        if (_selectedIndexes.contains(index)) {
                          _selectedIndexes.remove(index);
                        } else {
                          _selectedIndexes.add(index);
                        }
                      });
                    },
            ),
          ),
        Row(
          children: <Widget>[
            FilledButton.tonal(
              onPressed: _selectedIndexes.isEmpty ? null : _submitAnswer,
              child: Text(_submitted ? '已判定' : '提交答案'),
            ),
            if (_submitted) ...<Widget>[
              const SizedBox(width: 8),
              TextButton(onPressed: _resetAnswering, child: const Text('重新作答')),
            ],
          ],
        ),
        if (_submitted) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isCorrect
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isCorrect ? '回答正确' : '回答错误，正确答案：${_correctAnswerLabelText()}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isCorrect
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _switchMode(MultiChoiceBlockMode nextMode) {
    if (_mode == nextMode) {
      return;
    }
    setState(() {
      _mode = nextMode;
      _resetAnswerState();
    });
  }

  void _submitAnswer() {
    setState(() {
      _submitted = true;
    });
  }

  void _resetAnswering() {
    setState(_resetAnswerState);
  }

  void _resetAnswerState() {
    _selectedIndexes.clear();
    _submitted = false;
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
    _emitChanged();
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      return;
    }
    final TextEditingController controller = _optionControllers.removeAt(index);
    controller.dispose();

    final Set<int> nextCorrectIndexes = <int>{};
    for (final int correctIndex in _correctIndexes) {
      if (correctIndex == index) {
        continue;
      }
      nextCorrectIndexes.add(
        correctIndex > index ? correctIndex - 1 : correctIndex,
      );
    }
    if (nextCorrectIndexes.isEmpty && _optionControllers.isNotEmpty) {
      nextCorrectIndexes.add(0);
    }

    final Set<int> nextSelectedIndexes = <int>{};
    for (final int selectedIndex in _selectedIndexes) {
      if (selectedIndex == index) {
        continue;
      }
      nextSelectedIndexes.add(
        selectedIndex > index ? selectedIndex - 1 : selectedIndex,
      );
    }

    setState(() {
      _correctIndexes
        ..clear()
        ..addAll(nextCorrectIndexes);
      _selectedIndexes
        ..clear()
        ..addAll(nextSelectedIndexes);
      _submitted = false;
    });
    _emitChanged();
  }

  void _emitChanged() {
    final List<String> options = _optionControllers
        .map((TextEditingController controller) => controller.text)
        .toList(growable: false);
    final List<int> correctIndexes = _correctIndexes.toList()..sort();
    final MultiChoiceBlockData data = MultiChoiceBlockData(
      question: _questionController.text,
      options: options,
      correctIndexes: correctIndexes,
    ).normalized();
    widget.onChanged(data);
  }

  void _syncOptionControllers(List<String> options) {
    for (final TextEditingController controller in _optionControllers) {
      controller.dispose();
    }
    _optionControllers
      ..clear()
      ..addAll(
        options.map((String option) => TextEditingController(text: option)),
      );
  }

  void _scheduleAutofocusIfNeeded() {
    if (!widget.autofocusQuestion || _autofocusHandled) {
      return;
    }
    _autofocusHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _questionFocusNode.requestFocus();
      _questionController.selection = TextSelection.collapsed(
        offset: _questionController.text.length,
      );
    });
  }

  String _correctAnswerLabelText() {
    final List<int> indexes = _correctIndexes.toList()..sort();
    return indexes
        .map((int index) {
          final String text = index < _optionControllers.length
              ? _optionControllers[index].text.trim()
              : '';
          return '${_optionLabel(index)}. $text';
        })
        .join('；');
  }

  bool _setEquals(Set<int> left, Set<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final int item in left) {
      if (!right.contains(item)) {
        return false;
      }
    }
    return true;
  }

  bool _stringListEquals(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  bool _intListEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  String _optionLabel(int index) {
    return String.fromCharCode(65 + index);
  }
}

InputDecoration _embeddedFieldDecoration(
  BuildContext context, {
  bool isDense = false,
  String? labelText,
  String? hintText,
}) {
  final ThemeData theme = Theme.of(context);
  final Color borderColor = theme.colorScheme.outlineVariant.withValues(
    alpha: 0.65,
  );
  return InputDecoration(
    isDense: isDense,
    labelText: labelText,
    hintText: hintText,
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.78),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.2),
    ),
  );
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AnswerOptionTile extends StatelessWidget {
  const _AnswerOptionTile({
    required this.label,
    required this.text,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final String label;
  final String text;
  final bool selected;
  final bool correct;
  final bool wrong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color borderColor = correct
        ? theme.colorScheme.primary
        : wrong
        ? theme.colorScheme.error
        : selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final Color backgroundColor = correct
        ? theme.colorScheme.primaryContainer
        : wrong
        ? theme.colorScheme.errorContainer
        : selected
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: correct
                      ? theme.colorScheme.primary
                      : wrong
                      ? theme.colorScheme.error
                      : selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: correct || wrong || selected
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected || correct ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
