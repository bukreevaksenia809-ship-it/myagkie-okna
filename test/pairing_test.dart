import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/pairing.dart';

/// Генератор с предсказуемым `nextInt`.
class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value % max;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

const _window = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-014',
  windowType: WindowType.lifting,
  material: FilmMaterial.tintedPvc,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
  zippers: [ZipperSpec(centered: false, offsetMm: 400)],
  pocket: true,
  drainHoles: true,
  rollTop: 200,
);

const _project = OrderProject(windows: [_window, _window]);

Map<String, dynamic> _doc({
  required String id,
  required String orderJson,
  String name = 'Телефон замерщика',
  String summary = '2 окна · 6,00 м²',
}) =>
    {
      'name':
          'projects/okna-7dbf8/databases/(default)/documents/installations/'
              'okna-1/incoming/$id',
      'fields': {
        'adminKey': {'stringValue': Pairing.secret},
        'orderId': {'stringValue': id},
        'fromName': {'stringValue': name},
        'createdAt': {'timestampValue': '2026-10-26T09:15:00Z'},
        'status': {'stringValue': 'new'},
        'orderJson': {'stringValue': orderJson},
        'summary': {'stringValue': summary},
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('generateCode', () {
    test('всегда ровно 6 цифр', () {
      final random = Random(42);
      for (var i = 0; i < 300; i++) {
        final code = Pairing.generateCode(random);
        expect(code, matches(RegExp(r'^\d{6}$')), reason: 'код: $code');
        expect(code.length, Pairing.codeLength);
      }
    });

    test('ведущие нули сохраняются', () {
      expect(Pairing.generateCode(_FixedRandom(0)), '000000');
      expect(Pairing.generateCode(_FixedRandom(7)), '000007');
      expect(Pairing.generateCode(_FixedRandom(123)), '000123');
      expect(Pairing.generateCode(_FixedRandom(999999)), '999999');
    });

    test('нормализация и проверка кода', () {
      expect(Pairing.normalizeCode(' 123 456 '), '123456');
      expect(Pairing.normalizeCode('12-34-56'), '123456');
      expect(Pairing.isValidCode('000123'), isTrue);
      expect(Pairing.isValidCode('123456'), isTrue);
      expect(Pairing.isValidCode('12345'), isFalse);
      expect(Pairing.isValidCode('1234567'), isFalse);
      expect(Pairing.isValidCode('12 34 56'), isFalse);
    });
  });

  group('JSON заказа без сети', () {
    test('заказ сериализуется и читается обратно', () {
      final raw = Pairing.orderToJsonString(_project);
      expect(raw, isNotEmpty);

      final restored = Pairing.orderFromJsonString(raw);
      expect(restored, isNotNull);
      expect(restored!.windowCount, 2);
      expect(restored.windows.first.bottomWidth, 1500);
      expect(restored.windows.first.pocket, isTrue);
      // Сравниваем глубоко: порядок ключей в JSON не важен.
      expect(orderToJson(restored), orderToJson(_project));
    });

    test('битый JSON не бросает, а возвращает null', () {
      expect(Pairing.orderFromJsonString(null), isNull);
      expect(Pairing.orderFromJsonString(''), isNull);
      expect(Pairing.orderFromJsonString('   '), isNull);
      expect(Pairing.orderFromJsonString('не json'), isNull);
      expect(Pairing.orderFromJsonString('null'), isNull);
      expect(Pairing.orderFromJsonString('[1, 2, 3]'), isNull);
      expect(Pairing.orderFromJsonString('"строка"'), isNull);
    });

    test('сводка содержит количество окон и площадь', () {
      final two = Pairing.summaryText(_project);
      expect(two, contains('2 окна'));
      expect(two, contains('м²'));
      expect(Pairing.summaryText(const OrderProject(windows: [_window])),
          contains('1 окно'));
      expect(
        Pairing.summaryText(
          const OrderProject(windows: [_window, _window, _window, _window, _window]),
        ),
        contains('5 окон'),
      );
    });

    test('документ Firestore разбирается в IncomingOrder', () {
      final raw = Pairing.orderToJsonString(_project);
      final order = Pairing.incomingFromDocument(_doc(id: 'ord-1', orderJson: raw));
      expect(order, isNotNull);
      expect(order!.id, 'ord-1');
      expect(order.name, 'Телефон замерщика');
      expect(order.summary, '2 окна · 6,00 м²');
      expect(order.status, 'new');
      expect(order.project.windowCount, 2);
      expect(order.createdAt.toUtc(), DateTime.utc(2026, 10, 26, 9, 15));
    });

    test('документ с битым orderJson пропускается', () {
      expect(
        Pairing.incomingFromDocument(_doc(id: 'ord-2', orderJson: '{битый')),
        isNull,
      );
    });
  });

  group('тестовое окружение: сеть не трогаем', () {
    test('окружение распознано как тестовое', () {
      expect(Pairing.isTest, isTrue);
    });

    test('join не бросает и возвращает заглушку', () async {
      final result = await Pairing.join(' 123 456 ');
      expect(result.ok, isTrue);
      expect(result.code, '123456');
      expect(result.desktopInstallId, isNotEmpty);
      expect(result.desktopName, isNotEmpty);
    });

    test('join с неверным кодом не бросает', () async {
      final result = await Pairing.join('12');
      expect(result.ok, isFalse);
      expect(result.message, isNotEmpty);
      expect(Pairing.lastError, isNotEmpty);
    });

    test('sendOrder не бросает и возвращает id-заглушку', () async {
      final id = await Pairing.sendOrder(_project);
      expect(id, isNotNull);
      expect(id, isNotEmpty);
      expect(Pairing.lastError, isNull);
    });

    test('listIncoming/markImported/deleteIncoming не бросают', () async {
      expect(await Pairing.listIncoming(), isEmpty);
      expect(await Pairing.markImported('ord-1'), isFalse);
      expect(await Pairing.deleteIncoming('ord-1'), isFalse);
    });
  });
}
