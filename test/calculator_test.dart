import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/widgets/calculator.dart';

CalculatorEngine _engineWith(Iterable<String> tokens) {
  final engine = CalculatorEngine();
  for (final token in tokens) {
    engine.input(token);
  }
  return engine;
}

Future<void> _pumpCalculator(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: const Scaffold(body: Center(child: CalculatorDialog())),
    ),
  );
  await tester.pump();
}

Future<void> _tapKey(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('calculator-key-$id')));
  await tester.pump();
}

Future<void> _sendKey(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  PhysicalKeyboardKey? physicalKey,
  String? character,
}) async {
  await tester.sendKeyEvent(
    key,
    physicalKey: physicalKey,
    character: character,
  );
  await tester.pump();
}

String _displayText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

String _result(WidgetTester tester) =>
    _displayText(tester, 'calculator-result');

String _expressionText(WidgetTester tester) =>
    _displayText(tester, 'calculator-expression');

void main() {
  group('CalculatorEngine: живой результат', () {
    test('считает на каждом нажатии, без «=»', () {
      final engine = CalculatorEngine();
      expect(engine.result, '0');
      expect(engine.hasError, isFalse);

      engine.input('2');
      expect(engine.result, '2');

      engine.input('+');
      expect(engine.result, '2');

      engine.input('2');
      expect(engine.expression, '2+2');
      expect(engine.result, '4');
      expect(engine.hasError, isFalse);
    });

    test('приоритет операций: 2 + 2 × 2 = 6', () {
      final engine = _engineWith(<String>['2', '+', '2', '×', '2']);
      expect(engine.expression, '2+2*2');
      expect(engine.result, '6');
    });

    test('скобки: (2 + 2) × 2 = 8', () {
      final engine = _engineWith(<String>['(', '2', '+', '2', ')', '×', '2']);
      expect(engine.expression, '(2+2)*2');
      expect(engine.result, '8');
    });

    test('унарный минус', () {
      expect(_engineWith(<String>['-', '5', '+', '2']).result, '-3');
      expect(_engineWith(<String>['2', '×', '-', '3']).result, '-6');
      expect(_engineWith(<String>['(', '-', '5', ')', '×', '2']).result, '-10');
    });

    test('± меняет знак последнего операнда', () {
      final engine = _engineWith(<String>['5']);
      engine.toggleSign();
      expect(engine.expression, '-5');
      expect(engine.result, '-5');

      engine.toggleSign();
      expect(engine.expression, '5');
      expect(engine.result, '5');

      final sum = _engineWith(<String>['2', '+', '3']);
      sum.toggleSign();
      expect(sum.expression, '2+-3');
      expect(sum.result, '-1');
    });

    test('десятичная запятая и точка равнозначны', () {
      final comma = _engineWith(<String>['2', ',', '5']);
      expect(comma.expression, '2.5');
      expect(comma.result, '2.5');

      final dot = _engineWith(<String>['2', '.', '5']);
      expect(dot.expression, '2.5');
      expect(dot.result, '2.5');

      // Начало ввода с разделителя даёт «0,…».
      final leading = _engineWith(<String>[',', '5']);
      expect(leading.expression, '0.5');
      expect(leading.result, '0.5');
    });

    test('не тащит хвосты double: 0,1 + 0,2 = 0,3', () {
      final engine = _engineWith(<String>['0', ',', '1', '+', '0', ',', '2']);
      expect(engine.result, '0.3');
    });
  });

  group('CalculatorEngine: проценты', () {
    test('унарный процент: 50% → 0.5', () {
      final engine = _engineWith(<String>['5', '0', '%']);
      expect(engine.expression, '50%');
      expect(engine.result, '0.5');
      expect(engine.value, closeTo(0.5, 1e-12));
    });

    test('процент умножает операнд: 200 × 10% = 20', () {
      final engine = _engineWith(<String>['2', '0', '0', '×', '1', '0', '%']);
      expect(engine.result, '20');
    });

    test('проценты складываются как доли: 50% + 50% = 1', () {
      final engine = _engineWith(<String>['5', '0', '%', '+', '5', '0', '%']);
      expect(engine.result, '1');
    });
  });

  group('CalculatorEngine: ошибки и восстановление', () {
    test('деление на 0: аккуратный текст, без падения', () {
      final engine = _engineWith(<String>['1', '÷', '0']);
      expect(engine.hasError, isTrue);
      expect(engine.errorText, 'Деление на 0');
      expect(engine.result, 'Деление на 0');
      expect(engine.value, isNull);

      engine.input('AC');
      expect(engine.hasError, isFalse);
      expect(engine.expression, isEmpty);
      expect(engine.result, '0');
    });

    test('деление на 0 внутри скобок', () {
      final engine = _engineWith(<String>['1', '÷', '(', '2', '−', '2', ')']);
      expect(engine.hasError, isTrue);
      expect(engine.errorText, 'Деление на 0');
    });

    test('битое выражение показывает «Ошибка»', () {
      final engine = CalculatorEngine.fromExpression('2+*3');
      expect(engine.hasError, isTrue);
      expect(engine.errorText, 'Ошибка');
      expect(engine.result, 'Ошибка');

      expect(CalculatorEngine.fromExpression('()').errorText, 'Ошибка');
      expect(CalculatorEngine.fromExpression('2+3)').errorText, 'Ошибка');
    });

    test('недописанное выражение не считается ошибкой', () {
      expect(_engineWith(<String>['2', '+']).result, '2');
      expect(_engineWith(<String>['2', '+', '3', '×']).result, '5');
      expect(_engineWith(<String>['(', '2', '+', '3']).result, '5');
    });

    test('после ошибки backspace возвращает живой результат', () {
      final engine = _engineWith(<String>['1', '/', '0']);
      expect(engine.hasError, isTrue);
      engine.backspace();
      expect(engine.expression, '1/');
      expect(engine.hasError, isFalse);
      expect(engine.result, '1');
    });
  });

  group('CalculatorEngine: управление', () {
    test('backspace удаляет по символу', () {
      final engine = _engineWith(<String>['1', '2', '+', '3']);
      expect(engine.result, '15');

      engine.backspace();
      expect(engine.expression, '12+');
      expect(engine.result, '12');

      engine.backspace();
      expect(engine.expression, '12');
      expect(engine.result, '12');

      engine.backspace();
      engine.backspace();
      expect(engine.expression, isEmpty);
      expect(engine.result, '0');
    });

    test('AC очищает всё', () {
      final engine = _engineWith(<String>['9', '×', '9']);
      engine.input('AC');
      expect(engine.expression, isEmpty);
      expect(engine.result, '0');
      expect(engine.hasError, isFalse);
    });

    test('«=»/commit фиксирует результат и начинает новый ввод с цифры', () {
      final engine = _engineWith(<String>['2', '+', '2']);
      engine.commit();
      expect(engine.expression, '4');
      expect(engine.result, '4');

      engine.input('3');
      expect(engine.expression, '3');
      expect(engine.result, '3');
    });

    test('дисплей печатает ×, ÷, − и запятую', () {
      final engine = _engineWith(<String>['2', '×', '3', '−', '0', ',', '5']);
      expect(engine.expression, '2*3-0.5');
      expect(engine.displayExpression, '2×3−0,5');
    });
  });

  group('CalculatorDialog', () {
    testWidgets('нажатия: живой результат 2+2=4, приоритет даёт 6, AC', (
      tester,
    ) async {
      await _pumpCalculator(tester);

      await _tapKey(tester, '2');
      await _tapKey(tester, 'add');
      await _tapKey(tester, '2');

      expect(_expressionText(tester), '2+2');
      expect(_result(tester), '4');

      await _tapKey(tester, 'mul');
      await _tapKey(tester, '2');
      expect(_expressionText(tester), '2+2×2');
      expect(_result(tester), '6');

      await _tapKey(tester, 'clear');
      expect(_expressionText(tester), isEmpty);
      expect(_result(tester), '0');

      // Кнопки ±, запятой и backspace.
      await _tapKey(tester, 'sign');
      expect(_expressionText(tester), '−');
      await _tapKey(tester, '5');
      await _tapKey(tester, 'comma');
      await _tapKey(tester, '5');
      expect(_expressionText(tester), '−5,5');
      expect(_result(tester), '-5.5');

      await tester.tap(find.byKey(const Key('calculator-backspace')));
      await tester.pump();
      expect(_expressionText(tester), '−5,');
      expect(_result(tester), '-5');
    });

    testWidgets('клавиатура: цифры, оператор, Enter, Backspace, AC, запятая', (
      tester,
    ) async {
      await _pumpCalculator(tester, brightness: Brightness.dark);

      await _sendKey(tester, LogicalKeyboardKey.digit2);
      await _sendKey(
        tester,
        LogicalKeyboardKey.add,
        physicalKey: PhysicalKeyboardKey.equal,
        character: '+',
      );
      await _sendKey(tester, LogicalKeyboardKey.digit2);

      expect(_expressionText(tester), '2+2');
      expect(_result(tester), '4');

      await _sendKey(tester, LogicalKeyboardKey.enter);
      expect(_expressionText(tester), '4');
      expect(_result(tester), '4');

      await _sendKey(tester, LogicalKeyboardKey.digit7);
      expect(_expressionText(tester), '7');

      await _sendKey(tester, LogicalKeyboardKey.backspace);
      expect(_expressionText(tester), isEmpty);
      expect(_result(tester), '0');

      await _sendKey(tester, LogicalKeyboardKey.digit2);
      await _sendKey(tester, LogicalKeyboardKey.comma);
      await _sendKey(tester, LogicalKeyboardKey.digit5);
      expect(_expressionText(tester), '2,5');
      expect(_result(tester), '2.5');

      await _sendKey(tester, LogicalKeyboardKey.keyC);
      expect(_expressionText(tester), isEmpty);
      expect(_result(tester), '0');
    });

    testWidgets('showCalculator открывает диалог, Escape закрывает', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showCalculator(context),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(find.byType(CalculatorDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CalculatorDialog), findsNothing);
    });
  });
}
