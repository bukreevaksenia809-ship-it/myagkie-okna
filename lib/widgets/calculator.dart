import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Калькулятор в стиле Xiaomi/Android для вкладки «Чертёж».
///
/// Живой результат: выражение пересчитывается на каждом нажатии, без «=».
/// Enter фиксирует текущий результат (как «=»), Escape закрывает диалог.
/// Диалог живёт поверх листа, поэтому не попадает ни в снимок, ни в PDF,
/// ни в печать и не перехватывает жесты масштабирования/панорамирования.
Future<void> showCalculator(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => const CalculatorDialog(),
  );
}

/// Движок калькулятора: хранит выражение и живой результат.
///
/// Грамматика (рекурсивный спуск, без eval):
///
///     expression := term (('+' | '-') term)*
///     term       := unary (('*' | '/') unary)*
///     unary      := ('+' | '-') unary | postfix
///     postfix    := primary ('%')*
///     primary    := number | '(' expression ')'
///
/// `%` — унарный постфиксный оператор: переводит операнд в сотую долю
/// (50% → 0.5, 200 × 10% → 20). Деление на ноль и битые выражения не
/// роняют калькулятор: движок выставляет [hasError] и текст ошибки.
class CalculatorEngine {
  /// Пустой калькулятор: на дисплее 0.
  CalculatorEngine();

  /// Калькулятор с уже введённым выражением (восстановление/тесты).
  CalculatorEngine.fromExpression(String expression)
    : _expression = expression {
    _recalculate();
  }

  static final RegExp _trailingIncomplete = RegExp(r'[+\-*/.(]+$');
  static final RegExp _trailingZeros = RegExp(r'0+$');

  String _expression = '';
  String _resultText = '0';
  double? _value;
  _CalcFailure? _failure;
  bool _freshResult = false;

  /// Выражение в каноническом виде: `+ - * / ( ) %` и точка.
  String get expression => _expression;

  /// Выражение для экрана: `×`, `÷`, `−`, десятичная запятая.
  String get displayExpression => _expression
      .replaceAll('*', '×')
      .replaceAll('/', '÷')
      .replaceAll('.', ',')
      .replaceAll('-', '−');

  /// Живой результат или текст ошибки — то, что видно на нижней строке.
  String get result => _resultText;

  /// Текущее значение, если выражение посчиталось без ошибки.
  double? get value => _failure == null ? _value : null;

  /// Есть ли ошибка (деление на 0 или битое выражение).
  bool get hasError => _failure != null;

  /// Текст ошибки: «Деление на 0» или «Ошибка»; пусто, если ошибки нет.
  String get errorText => _failure?.message ?? '';

  /// Вводит один токен: цифру, `.`/`,`, `+ - * /`, `(`/`)`, `%`, `±`,
  /// `AC` или `=`.
  void input(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (trimmed.length > 1) {
      switch (trimmed.toUpperCase()) {
        case 'AC':
        case 'C':
        case 'CLEAR':
          clear();
        case 'BACKSPACE':
        case 'DEL':
          backspace();
        case 'COMMIT':
          commit();
        case 'NEGATE':
          toggleSign();
      }
      return;
    }
    final char = switch (trimmed) {
      '×' => '*',
      '÷' => '/',
      '−' || '–' || '—' => '-',
      ',' => '.',
      _ => trimmed,
    };
    if (_isDigit(char)) {
      _appendDigit(char);
    } else if (char == '.') {
      _appendDecimal();
    } else if (char == '+' || char == '-' || char == '*' || char == '/') {
      _appendOperator(char);
    } else if (char == '(') {
      _appendOpenParen();
    } else if (char == ')') {
      _appendCloseParen();
    } else if (char == '%') {
      _appendPercent();
    } else if (char == '±') {
      toggleSign();
      return;
    } else if (char == '=') {
      commit();
      return;
    } else {
      return;
    }
    _recalculate();
  }

  /// Удаляет последний символ выражения.
  void backspace() {
    _freshResult = false;
    if (_expression.isEmpty) {
      _recalculate();
      return;
    }
    _expression = _expression.substring(0, _expression.length - 1);
    _recalculate();
  }

  /// Полный сброс (AC).
  void clear() {
    _expression = '';
    _freshResult = false;
    _failure = null;
    _value = null;
    _resultText = '0';
  }

  /// Меняет знак текущего (последнего) операнда.
  void toggleSign() {
    _freshResult = false;
    if (_expression.isEmpty) {
      _expression = '-';
      _recalculate();
      return;
    }
    // Уже висящий унарный минус (в начале, после оператора или скобки).
    if (_isUnaryMinusAtEnd()) {
      _expression = _expression.substring(0, _expression.length - 1);
      _recalculate();
      return;
    }
    final start = _trailingOperandStart();
    if (start == null) {
      final last = _lastChar;
      if (_isBinaryOperator(last) || last == '(') {
        _expression += '-';
        _recalculate();
      }
      return;
    }
    final hasUnaryMinus =
        start > 0 &&
        _expression[start - 1] == '-' &&
        (start - 1 == 0 ||
            _isBinaryOperator(_expression[start - 2]) ||
            _expression[start - 2] == '(');
    if (hasUnaryMinus) {
      _expression =
          '${_expression.substring(0, start - 1)}'
          '${_expression.substring(start)}';
    } else {
      _expression =
          '${_expression.substring(0, start)}-'
          '${_expression.substring(start)}';
    }
    _recalculate();
  }

  /// Фиксирует живой результат («=» / Enter): результат становится
  /// выражением, чтобы с ним можно было продолжить считать.
  void commit() {
    if (_failure != null || _value == null || _expression.isEmpty) {
      return;
    }
    _expression = _formatNumber(_value!);
    _freshResult = true;
    _recalculate();
  }

  // ---------------------------------------------------------------------
  // Ввод
  // ---------------------------------------------------------------------

  String get _lastChar =>
      _expression.isEmpty ? '' : _expression[_expression.length - 1];

  bool _isUnaryMinusAtEnd() {
    if (_lastChar != '-') {
      return false;
    }
    if (_expression.length == 1) {
      return true;
    }
    final before = _expression[_expression.length - 2];
    return _isBinaryOperator(before) || before == '(';
  }

  /// Начало последнего простого операнда (число или скобка) с хвостом `%`.
  int? _trailingOperandStart() {
    if (_expression.isEmpty) {
      return null;
    }
    var end = _expression.length;
    while (end > 0 && _expression[end - 1] == '%') {
      end--;
    }
    if (end == 0) {
      return null;
    }
    final last = _expression[end - 1];
    if (last == ')') {
      var depth = 0;
      for (var i = end - 1; i >= 0; i--) {
        final char = _expression[i];
        if (char == ')') {
          depth++;
        } else if (char == '(') {
          depth--;
          if (depth == 0) {
            return i;
          }
        }
      }
      return null;
    }
    if (!_isDigit(last) && last != '.') {
      return null;
    }
    var start = end;
    while (start > 0 &&
        (_isDigit(_expression[start - 1]) || _expression[start - 1] == '.')) {
      start--;
    }
    return start;
  }

  int _trailingNumberStart() {
    var index = _expression.length;
    while (index > 0) {
      final char = _expression[index - 1];
      if (_isDigit(char) || char == '.') {
        index--;
      } else {
        break;
      }
    }
    return index;
  }

  void _appendDigit(String digit) {
    if (_freshResult) {
      _expression = '';
      _freshResult = false;
    }
    final last = _lastChar;
    if (last == ')' || last == '%') {
      // Неявное умножение: 2(3+1), 50%2.
      _expression += '*';
    }
    final start = _trailingNumberStart();
    if (_expression.substring(start) == '0') {
      _expression = _expression.substring(0, start) + digit;
    } else {
      _expression += digit;
    }
  }

  void _appendDecimal() {
    if (_freshResult) {
      _expression = '';
      _freshResult = false;
    }
    final last = _lastChar;
    if (last == ')' || last == '%') {
      _expression += '*0.';
      return;
    }
    final start = _trailingNumberStart();
    final segment = _expression.substring(start);
    if (segment.contains('.')) {
      return;
    }
    _expression += segment.isEmpty ? '0.' : '.';
  }

  void _appendOperator(String operator) {
    _freshResult = false;
    if (_expression.isEmpty) {
      if (operator == '-') {
        _expression = '-';
      }
      return;
    }
    var last = _lastChar;
    if (last == '(') {
      if (operator == '-') {
        _expression += '-';
      }
      return;
    }
    if (_isUnaryMinusAtEnd()) {
      _expression = _expression.substring(0, _expression.length - 1);
      if (_expression.isEmpty) {
        if (operator == '-') {
          _expression = '-';
        }
        return;
      }
      last = _lastChar;
      if (_isBinaryOperator(last)) {
        _expression =
            _expression.substring(0, _expression.length - 1) + operator;
      } else {
        _expression += operator;
      }
      return;
    }
    if (_isBinaryOperator(last)) {
      if (operator == '-' && (last == '*' || last == '/')) {
        _expression += '-';
      } else {
        _expression =
            _expression.substring(0, _expression.length - 1) + operator;
      }
      return;
    }
    _expression += operator;
  }

  void _appendOpenParen() {
    _freshResult = false;
    final last = _lastChar;
    if (_isDigit(last) || last == ')' || last == '%' || last == '.') {
      _expression += '*';
    }
    _expression += '(';
  }

  void _appendCloseParen() {
    _freshResult = false;
    if (_openParenCount(_expression) <= 0) {
      return;
    }
    final last = _lastChar;
    if (!(_isDigit(last) || last == ')' || last == '%')) {
      return;
    }
    _expression += ')';
  }

  void _appendPercent() {
    _freshResult = false;
    final last = _lastChar;
    if (!(_isDigit(last) || last == ')' || last == '%')) {
      return;
    }
    _expression += '%';
  }

  // ---------------------------------------------------------------------
  // Подсчёт
  // ---------------------------------------------------------------------

  void _recalculate() {
    _failure = null;
    _value = null;
    if (_expression.isEmpty) {
      _resultText = '0';
      return;
    }
    try {
      final evaluated = _evaluateWithTolerance(_expression);
      if (evaluated == null) {
        _resultText = '0';
        return;
      }
      _value = evaluated;
      _resultText = _formatNumber(evaluated);
    } on _CalcFailure catch (failure) {
      _failure = failure;
      _resultText = failure.message;
    }
  }

  /// Считает выражение, а недописанное (хвостовой оператор, незакрытая
  /// скобка) аккуратно достраивает, чтобы живой результат не мигал.
  double? _evaluateWithTolerance(String source) {
    try {
      return _evaluateStrict(source);
    } on _CalcFailure catch (failure) {
      if (failure.kind != _CalcFailureKind.incomplete) {
        rethrow;
      }
    }
    var candidate = source;
    while (candidate.isNotEmpty) {
      candidate = candidate.replaceFirst(_trailingIncomplete, '');
      if (candidate.isEmpty) {
        return null;
      }
      final missingParens = math.max(0, _openParenCount(candidate));
      final completed = candidate + (')' * missingParens);
      try {
        return _evaluateStrict(completed);
      } on _CalcFailure catch (failure) {
        if (failure.kind != _CalcFailureKind.incomplete) {
          rethrow;
        }
      }
      candidate = candidate.substring(0, candidate.length - 1);
    }
    return null;
  }

  static double _evaluateStrict(String source) {
    final tokens = _tokenize(source);
    if (tokens.isEmpty) {
      throw const _CalcFailure(_CalcFailureKind.incomplete, '');
    }
    final parser = _ExpressionParser(tokens);
    final value = parser.parseExpression();
    if (!parser.isAtEnd) {
      throw _malformed;
    }
    if (!value.isFinite) {
      throw _malformed;
    }
    return value;
  }

  static List<_Token> _tokenize(String source) {
    final tokens = <_Token>[];
    var index = 0;
    while (index < source.length) {
      final char = source[index];
      if (char == ' ') {
        index++;
        continue;
      }
      if (_isDigit(char) || char == '.') {
        final start = index;
        var hasDot = false;
        while (index < source.length) {
          final current = source[index];
          if (_isDigit(current)) {
            index++;
            continue;
          }
          if (current == '.') {
            if (hasDot) {
              throw _malformed;
            }
            hasDot = true;
            index++;
            continue;
          }
          break;
        }
        final text = source.substring(start, index);
        if (text == '.') {
          throw _malformed;
        }
        final value = double.tryParse(text);
        if (value == null || !value.isFinite) {
          throw _malformed;
        }
        tokens.add(_Token(_TokenType.number, value));
        continue;
      }
      final type = switch (char) {
        '+' => _TokenType.plus,
        '-' => _TokenType.minus,
        '*' || '×' => _TokenType.times,
        '/' || '÷' => _TokenType.divide,
        '%' => _TokenType.percent,
        '(' => _TokenType.openParen,
        ')' => _TokenType.closeParen,
        _ => null,
      };
      if (type == null) {
        throw _malformed;
      }
      tokens.add(_Token(type));
      index++;
    }
    return tokens;
  }

  static int _openParenCount(String source) {
    var open = 0;
    for (final unit in source.codeUnits) {
      if (unit == 0x28) {
        open++;
      } else if (unit == 0x29) {
        open--;
      }
    }
    return open < 0 ? 0 : open;
  }

  static String _formatNumber(double value) {
    if (!value.isFinite) {
      throw _malformed;
    }
    if (value == 0) {
      return '0';
    }
    final abs = value.abs();
    if (abs < 1e15 && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    final precise = value.toStringAsPrecision(12);
    if (precise.contains('e') || precise.contains('E')) {
      return _formatExponential(value);
    }
    var text = precise.replaceFirst(_trailingZeros, '');
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  static String _formatExponential(double value) {
    final text = value.toStringAsExponential(10);
    final marker = text.indexOf('e');
    var mantissa = text.substring(0, marker);
    final exponent = int.tryParse(text.substring(marker + 1));
    if (mantissa.contains('.')) {
      mantissa = mantissa.replaceFirst(_trailingZeros, '');
      if (mantissa.endsWith('.')) {
        mantissa = mantissa.substring(0, mantissa.length - 1);
      }
    }
    return exponent == null ? text : '${mantissa}e$exponent';
  }
}

const _CalcFailure _malformed = _CalcFailure(
  _CalcFailureKind.malformed,
  'Ошибка',
);

bool _isDigit(String char) {
  if (char.length != 1) {
    return false;
  }
  final code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

bool _isBinaryOperator(String char) =>
    char == '+' || char == '-' || char == '*' || char == '/';

enum _CalcFailureKind { incomplete, malformed, divisionByZero }

class _CalcFailure implements Exception {
  const _CalcFailure(this.kind, this.message);

  final _CalcFailureKind kind;
  final String message;

  @override
  String toString() => 'CalcFailure($kind): $message';
}

enum _TokenType {
  number,
  plus,
  minus,
  times,
  divide,
  percent,
  openParen,
  closeParen,
}

class _Token {
  const _Token(this.type, [this.value]);

  final _TokenType type;
  final double? value;
}

class _ExpressionParser {
  _ExpressionParser(this.tokens);

  final List<_Token> tokens;
  int _position = 0;

  bool get isAtEnd => _position >= tokens.length;

  _Token? get _current => _position < tokens.length ? tokens[_position] : null;

  double parseExpression() {
    var value = parseTerm();
    while (true) {
      final token = _current;
      if (token == null) {
        break;
      }
      if (token.type == _TokenType.plus) {
        _position++;
        value += parseTerm();
      } else if (token.type == _TokenType.minus) {
        _position++;
        value -= parseTerm();
      } else {
        break;
      }
    }
    return value;
  }

  double parseTerm() {
    var value = parseUnary();
    while (true) {
      final token = _current;
      if (token == null) {
        break;
      }
      if (token.type == _TokenType.times) {
        _position++;
        value *= parseUnary();
      } else if (token.type == _TokenType.divide) {
        _position++;
        final divisor = parseUnary();
        if (divisor == 0) {
          throw const _CalcFailure(
            _CalcFailureKind.divisionByZero,
            'Деление на 0',
          );
        }
        value /= divisor;
      } else {
        break;
      }
    }
    return value;
  }

  double parseUnary() {
    final token = _current;
    if (token == null) {
      throw const _CalcFailure(_CalcFailureKind.incomplete, '');
    }
    if (token.type == _TokenType.plus) {
      _position++;
      return parseUnary();
    }
    if (token.type == _TokenType.minus) {
      _position++;
      return -parseUnary();
    }
    return parsePostfix();
  }

  double parsePostfix() {
    var value = parsePrimary();
    while (_current?.type == _TokenType.percent) {
      _position++;
      value /= 100;
    }
    return value;
  }

  double parsePrimary() {
    final token = _current;
    if (token == null) {
      throw const _CalcFailure(_CalcFailureKind.incomplete, '');
    }
    switch (token.type) {
      case _TokenType.number:
        _position++;
        return token.value!;
      case _TokenType.openParen:
        _position++;
        final value = parseExpression();
        final closing = _current;
        if (closing == null) {
          throw const _CalcFailure(_CalcFailureKind.incomplete, '');
        }
        if (closing.type != _TokenType.closeParen) {
          throw _malformed;
        }
        _position++;
        return value;
      case _TokenType.plus:
      case _TokenType.minus:
      case _TokenType.times:
      case _TokenType.divide:
      case _TokenType.percent:
      case _TokenType.closeParen:
        throw _malformed;
    }
  }
}

/// Модальное окно калькулятора. Тонкая обёртка над [CalculatorEngine].
class CalculatorDialog extends StatefulWidget {
  const CalculatorDialog({super.key});

  @override
  State<CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<CalculatorDialog> {
  final CalculatorEngine _engine = CalculatorEngine();
  final FocusNode _focusNode = FocusNode(debugLabel: 'calculator');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('calculator-dialog'),
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: SizedBox(
          width: math.min(420, math.max(0, screen.width - 32)),
          height: math.min(680, math.max(0, screen.height - 32)),
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: isDark ? 0 : 12,
            shadowColor: scheme.shadow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: isDark
                  ? BorderSide(color: scheme.outlineVariant)
                  : BorderSide.none,
            ),
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(flex: 4, child: _buildDisplay(context)),
                Expanded(flex: 6, child: _buildKeypad(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Icon(
              Icons.calculate_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              'Калькулятор',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            ExcludeFocus(
              child: IconButton(
                key: const Key('calculator-backspace'),
                tooltip: 'Удалить последний символ',
                onPressed: _backspace,
                color: scheme.onSurfaceVariant,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ),
            ExcludeFocus(
              child: IconButton(
                key: const Key('calculator-close'),
                tooltip: 'Закрыть',
                onPressed: _close,
                color: scheme.onSurfaceVariant,
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplay(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomRight,
                child: Text(
                  _engine.displayExpression,
                  key: const Key('calculator-expression'),
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.bottomRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomRight,
                child: Semantics(
                  liveRegion: true,
                  label: 'Результат: ${_engine.result}',
                  child: Text(
                    _engine.result,
                    key: const Key('calculator-result'),
                    maxLines: 1,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: _engine.hasError ? scheme.error : scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(
        children: [
          for (final row in _keypadRows)
            Expanded(
              child: Row(
                children: [
                  for (final spec in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _CalcKey(
                          spec: spec,
                          background: _backgroundFor(scheme, spec.kind),
                          foreground: _foregroundFor(scheme, spec.kind),
                          onTap: () => _press(spec.token),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _press(String token) {
    setState(() => _engine.input(token));
  }

  void _backspace() {
    setState(() => _engine.backspace());
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      setState(() => _engine.commit());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _backspace();
      return KeyEventResult.handled;
    }
    final token = _tokenFor(event);
    if (token == null) {
      return KeyEventResult.ignored;
    }
    _press(token);
    return KeyEventResult.handled;
  }

  String? _tokenFor(KeyEvent event) {
    final character = event.character;
    if (character != null && character.length == 1) {
      final token = _tokenForCharacter(character);
      if (token != null) {
        return token;
      }
    }
    return _fallbackKeyTokens[event.logicalKey];
  }

  String? _tokenForCharacter(String character) {
    if (_isDigit(character)) {
      return character;
    }
    return switch (character) {
      ',' || '.' => '.',
      '+' || '-' || '*' || '/' || '%' || '(' || ')' => character,
      '×' => '*',
      '÷' => '/',
      '−' || '–' => '-',
      '=' => '=',
      'c' || 'C' => 'AC',
      _ => null,
    };
  }

  Color _backgroundFor(ColorScheme scheme, _KeyKind kind) {
    return switch (kind) {
      _KeyKind.digit => scheme.surfaceContainerHighest,
      _KeyKind.function => scheme.secondaryContainer,
      _KeyKind.operator || _KeyKind.equals => scheme.primary,
    };
  }

  Color _foregroundFor(ColorScheme scheme, _KeyKind kind) {
    return switch (kind) {
      _KeyKind.digit => scheme.onSurface,
      _KeyKind.function => scheme.onSecondaryContainer,
      _KeyKind.operator || _KeyKind.equals => scheme.onPrimary,
    };
  }

  static const List<List<_KeySpec>> _keypadRows = <List<_KeySpec>>[
    <_KeySpec>[
      _KeySpec('clear', 'AC', 'AC', _KeyKind.function),
      _KeySpec('open', '(', '(', _KeyKind.function),
      _KeySpec('close', ')', ')', _KeyKind.function),
      _KeySpec('percent', '%', '%', _KeyKind.function),
    ],
    <_KeySpec>[
      _KeySpec('7', '7', '7', _KeyKind.digit),
      _KeySpec('8', '8', '8', _KeyKind.digit),
      _KeySpec('9', '9', '9', _KeyKind.digit),
      _KeySpec('div', '÷', '/', _KeyKind.operator),
    ],
    <_KeySpec>[
      _KeySpec('4', '4', '4', _KeyKind.digit),
      _KeySpec('5', '5', '5', _KeyKind.digit),
      _KeySpec('6', '6', '6', _KeyKind.digit),
      _KeySpec('mul', '×', '*', _KeyKind.operator),
    ],
    <_KeySpec>[
      _KeySpec('1', '1', '1', _KeyKind.digit),
      _KeySpec('2', '2', '2', _KeyKind.digit),
      _KeySpec('3', '3', '3', _KeyKind.digit),
      _KeySpec('sub', '−', '-', _KeyKind.operator),
    ],
    <_KeySpec>[
      _KeySpec('sign', '±', '±', _KeyKind.function),
      _KeySpec('0', '0', '0', _KeyKind.digit),
      _KeySpec('comma', ',', '.', _KeyKind.function),
      _KeySpec('add', '+', '+', _KeyKind.operator),
    ],
    <_KeySpec>[_KeySpec('equals', '=', '=', _KeyKind.equals)],
  ];
}

class _CalcKey extends StatelessWidget {
  const _CalcKey({
    required this.spec,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final _KeySpec spec;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = switch (spec.kind) {
      _KeyKind.digit => 26.0,
      _KeyKind.function => 22.0,
      _KeyKind.operator => 28.0,
      _KeyKind.equals => 30.0,
    };
    final radius = BorderRadius.circular(22);
    return Material(
      color: background,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('calculator-key-${spec.id}'),
        onTap: onTap,
        canRequestFocus: false,
        borderRadius: radius,
        hoverColor: foreground.withValues(alpha: 0.08),
        highlightColor: foreground.withValues(alpha: 0.16),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                spec.label,
                maxLines: 1,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: foreground,
                  fontSize: fontSize,
                  fontWeight: spec.kind == _KeyKind.digit
                      ? FontWeight.w400
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _KeyKind { digit, function, operator, equals }

class _KeySpec {
  const _KeySpec(this.id, this.label, this.token, this.kind);

  final String id;
  final String label;
  final String token;
  final _KeyKind kind;
}

final Map<LogicalKeyboardKey, String> _fallbackKeyTokens =
    <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.digit0: '0',
      LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.digit2: '2',
      LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.digit4: '4',
      LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.digit6: '6',
      LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.digit8: '8',
      LogicalKeyboardKey.digit9: '9',
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.numpad9: '9',
      LogicalKeyboardKey.add: '+',
      LogicalKeyboardKey.minus: '-',
      LogicalKeyboardKey.asterisk: '*',
      LogicalKeyboardKey.slash: '/',
      LogicalKeyboardKey.percent: '%',
      LogicalKeyboardKey.parenthesisLeft: '(',
      LogicalKeyboardKey.parenthesisRight: ')',
      LogicalKeyboardKey.period: '.',
      LogicalKeyboardKey.comma: '.',
      LogicalKeyboardKey.equal: '=',
      LogicalKeyboardKey.numpadAdd: '+',
      LogicalKeyboardKey.numpadSubtract: '-',
      LogicalKeyboardKey.numpadMultiply: '*',
      LogicalKeyboardKey.numpadDivide: '/',
      LogicalKeyboardKey.numpadDecimal: '.',
    };
