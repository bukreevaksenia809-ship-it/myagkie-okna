import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_json.dart';
import '../models/order_project.dart';
import 'costs_summary.dart';
import 'device_scan_io.dart'
    if (dart.library.js_interop) 'device_scan_web.dart' as device;
import 'telemetry.dart';
import 'test_env_io.dart'
    if (dart.library.js_interop) 'test_env_web.dart' as test_env;

/// Связь «телефон замерщика ↔ компьютер» по 6-значному коду.
///
/// Схема (Firestore REST, проект okna-7dbf8):
///
/// ```
/// pairings/{code}                     — код компьютера и его installId
/// pairings/{code}/devices/{installId} — подключённые телефоны
/// installations/{desktopInstallId}/incoming/{orderId} — заказы с телефона
/// ```
///
/// Компьютер создаёт код ([createCode]) и показывает его замерщику. Телефон
/// вводит код ([join]) и отправляет заказы ([sendOrder]). Компьютер читает
/// входящие ([listIncoming]), отмечает импортированные ([markImported]) или
/// удаляет их ([deleteIncoming]).
///
/// Все методы не бросают исключений: сеть/таймаут/битый JSON превращаются в
/// `null`, `false` или пустой список, а текст последней ошибки лежит в
/// [lastError]. В тестовом окружении (`FLUTTER_TEST`) сеть не трогается —
/// методы возвращают заглушки, чтобы UI-тесты работали без Firestore.
class Pairing {
  Pairing._();

  // ------------------------------------------------------------- настройки

  static const String projectId = 'okna-7dbf8';
  static const String apiKey = 'AIzaSyAwOQn1TDzcApHt1PKmhxoQfFAtraYSaA4';
  static const String secret = 'okna-b0ZHSRJIz3XqCnQtsbL0FXBxHu4j';

  static const String _base =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  /// Сколько цифр в коде подключения.
  static const int codeLength = 6;

  /// Таймаут одного запроса Firestore.
  static const Duration timeout = Duration(seconds: 8);

  /// Сколько входящих заказов читать за один раз.
  static const int incomingLimit = 100;

  // --------------------------------------------------------- ключи prefs

  /// Код, созданный на этом компьютере.
  static const String prefsCode = 'pairing_code';

  /// Когда создан код компьютера (ISO-8601, UTC).
  static const String prefsCreatedAt = 'pairing_created_at';

  /// Имя компьютера, сохранённое вместе с кодом.
  static const String prefsDesktopName = 'pairing_desktop_name';

  /// Код компьютера, к которому подключён телефон.
  static const String prefsPairedCode = 'paired_code';

  /// installId компьютера, к которому подключён телефон.
  static const String prefsPairedInstallId = 'paired_desktop_install_id';

  /// Имя компьютера, к которому подключён телефон.
  static const String prefsPairedName = 'paired_desktop_name';

  /// Имя этого устройства (телефона), показанное компьютеру.
  static const String prefsDeviceName = 'pairing_device_name';

  /// Текст последней ошибки. `null` — последний вызов прошёл без ошибок.
  static String? lastError;

  /// В тестовом окружении Firestore не трогаем.
  static bool get isTest => test_env.isTestEnvironment;

  // ------------------------------------------------------ чистые helper-ы

  /// Случайный 6-значный код. Ведущие нули сохраняются: `000123`.
  ///
  /// [random] нужен тестам; в приложении берётся криптостойкий генератор.
  static String generateCode([Random? random]) {
    final rng = random ?? _secureRandom();
    final value = rng.nextInt(1000000);
    return value.toString().padLeft(codeLength, '0');
  }

  /// Оставляет в строке только цифры: `«123 456»` → `«123456»`.
  static String normalizeCode(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  /// Ровно 6 цифр (после [normalizeCode]).
  static bool isValidCode(String raw) =>
      RegExp(r'^\d{6}$').hasMatch(raw);

  /// Заказ → строка JSON для поля `orderJson`.
  static String orderToJsonString(OrderProject project) =>
      jsonEncode(orderToJson(project));

  /// Строка JSON → заказ. `null`, если JSON битый или не похож на заказ.
  ///
  /// Отсутствующие поля заполняются значениями по умолчанию — этим занимается
  /// [orderFromJson], поэтому старые заказы читаются без ошибок.
  static OrderProject? orderFromJsonString(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return orderFromJson(decoded);
      if (decoded is Map) return orderFromJson(decoded.cast<String, dynamic>());
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Подпись заказа для списка входящих: «3 окна · 12,40 м²».
  static String summaryText(OrderProject project) {
    final windows = _windowsLabel(project.windowCount);
    final area = _areaM2(project);
    return '$windows · ${area.toStringAsFixed(2).replaceAll('.', ',')} м²';
  }

  /// Документ Firestore (ответ REST) → входящий заказ.
  ///
  /// Возвращает `null`, если в документе нет корректного `orderJson`: такой
  /// заказ всё равно нельзя импортировать. Имя документа становится [id].
  static IncomingOrder? incomingFromDocument(Map<String, dynamic> document) {
    final name = document['name'];
    final fields = _fieldsOf(document);
    final project = orderFromJsonString(_stringOf(fields['orderJson']));
    if (project == null) return null;
    final id = name is String ? name.split('/').last : '';
    if (id.isEmpty) return null;
    final created = _dateOf(fields['createdAt']);
    final summary = _stringOf(fields['summary']);
    return IncomingOrder(
      id: id,
      name: _stringOf(fields['fromName'], 'Компьютер'),
      createdAt: created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      project: project,
      summary: summary.isEmpty ? summaryText(project) : summary,
      fromInstallId: _stringOf(fields['fromInstallId']),
      status: _stringOf(fields['status'], 'new'),
    );
  }

  // ----------------------------------------------------- компьютер (ПК)

  /// Создаёт новый код компьютера и публикует его в `pairings/{code}`.
  ///
  /// Старый код (если был) деактивируется, новый сохраняется в prefs
  /// (`pairing_code`, `pairing_created_at`). `null` — не удалось (текст в
  /// [lastError]).
  static Future<PairingCode?> createCode({String? desktopName}) async {
    lastError = null;
    if (isTest) {
      return PairingCode(
        code: generateCode(),
        createdAt: DateTime.now().toUtc(),
        desktopName: (desktopName ?? 'Тестовый ПК').trim(),
      );
    }
    try {
      final installId = await _installId();
      if (installId == null) {
        lastError = 'Не удалось определить установку';
        return null;
      }
      final name = _cleanName(desktopName) ?? await _deviceName();
      final preferred = await _prefsString(prefsDesktopName);
      final desktopLabel = name.isEmpty ? (preferred ?? 'Компьютер') : name;

      String? code;
      for (var attempt = 0; attempt < 5; attempt++) {
        final candidate = generateCode();
        if (await _isCodeFree(candidate)) {
          code = candidate;
          break;
        }
      }
      if (code == null) {
        lastError = 'Не удалось подобрать свободный код';
        return null;
      }

      final oldCode = await _prefsString(prefsCode);
      if (oldCode != null &&
          oldCode != code &&
          isValidCode(oldCode)) {
        // Старый код больше не должен пускать новые телефоны. Ошибку здесь
        // игнорируем: главное — выдать рабочий новый код.
        await _patch(
          'pairings/$oldCode',
          {'adminKey': _s(secret), 'active': _b(false)},
          mask: const ['active'],
        );
      }

      final now = DateTime.now().toUtc();
      final response = await _patch('pairings/$code', {
        'adminKey': _s(secret),
        'code': _s(code),
        'desktopInstallId': _s(installId),
        'desktopName': _s(desktopLabel),
        'createdAt': _ts(now),
        'lastSeen': _ts(now),
        'active': _b(true),
      });
      if (response == null) {
        lastError ??= 'Нет связи с сервером';
        return null;
      }
      if (!_ok(response)) {
        lastError = 'Не удалось создать код (${response.statusCode})';
        return null;
      }

      await _saveDesktopCode(code, now, desktopLabel);
      return PairingCode(
        code: code,
        createdAt: now,
        desktopName: desktopLabel,
      );
    } catch (_) {
      lastError = 'Не удалось создать код';
      return null;
    }
  }

  /// Код компьютера из prefs. Сеть не нужна; `null`, если кода нет.
  static Future<PairingCode?> currentCode() async {
    final code = await _prefsString(prefsCode);
    if (code == null || !isValidCode(code)) return null;
    final created = _dateOf(await _prefsString(prefsCreatedAt)) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return PairingCode(
      code: code,
      createdAt: created,
      desktopName: await _prefsString(prefsDesktopName) ?? '',
    );
  }

  /// Продлевает `lastSeen` текущего кода компьютера.
  static Future<bool> touch() async {
    lastError = null;
    if (isTest) return false;
    final saved = await currentCode();
    if (saved == null) {
      lastError = 'Код ещё не создан';
      return false;
    }
    final response = await _patch(
      'pairings/${saved.code}',
      {
        'adminKey': _s(secret),
        'lastSeen': _ts(DateTime.now().toUtc()),
      },
      mask: const ['lastSeen'],
    );
    if (response == null) {
      lastError ??= 'Нет связи с сервером';
      return false;
    }
    if (!_ok(response)) {
      lastError = 'Не удалось продлить код (${response.statusCode})';
      return false;
    }
    return true;
  }

  /// Выключает текущий код компьютера и убирает его из prefs.
  static Future<bool> deactivateCode() async {
    lastError = null;
    if (isTest) return false;
    final saved = await currentCode();
    if (saved == null) {
      lastError = 'Код ещё не создан';
      return false;
    }
    final response = await _patch(
      'pairings/${saved.code}',
      {'adminKey': _s(secret), 'active': _b(false)},
      mask: const ['active'],
    );
    if (response == null) {
      lastError ??= 'Нет связи с сервером';
      return false;
    }
    if (!_ok(response)) {
      lastError = 'Не удалось выключить код (${response.statusCode})';
      return false;
    }
    await _clearDesktopCode();
    return true;
  }

  // -------------------------------------------------------- телефон

  /// Подключается к компьютеру по 6-значному коду.
  ///
  /// Проверяет код в `pairings/{code}`, создаёт
  /// `pairings/{code}/devices/{installId}` и сохраняет в prefs `paired_code`
  /// (плюс installId и имя компьютера для [sendOrder]).
  static Future<PairingResult> join(String rawCode, {String? name}) async {
    lastError = null;
    final code = normalizeCode(rawCode);
    if (!isValidCode(code)) {
      lastError = 'Код должен состоять из 6 цифр';
      return PairingResult.failure(lastError!);
    }
    if (isTest) {
      return PairingResult.success(
        code: code,
        desktopInstallId: 'test-desktop',
        desktopName: 'Тестовый ПК',
      );
    }
    try {
      final response = await _get('pairings/$code');
      if (response == null) {
        lastError = 'Нет связи с сервером';
        return PairingResult.failure(lastError!);
      }
      if (response.statusCode == 404) {
        lastError = 'Код не найден — проверьте цифры на компьютере';
        return PairingResult.failure(lastError!);
      }
      if (!_ok(response)) {
        lastError = 'Сервер ответил ${response.statusCode}';
        return PairingResult.failure(lastError!);
      }
      final document = _decodeDocument(response);
      if (document == null) {
        lastError = 'Сервер вернул пустой ответ';
        return PairingResult.failure(lastError!);
      }
      final fields = _fieldsOf(document);
      if (fields['active'] != true) {
        lastError = 'Код устарел — обновите его на компьютере';
        return PairingResult.failure(lastError!);
      }
      final desktopInstallId = _stringOf(fields['desktopInstallId']);
      if (desktopInstallId.isEmpty) {
        lastError = 'Код не привязан к компьютеру';
        return PairingResult.failure(lastError!);
      }
      final desktopName =
          _stringOf(fields['desktopName'], 'Компьютер').trim();
      final installId = await _installId();
      if (installId == null) {
        lastError = 'Не удалось определить установку';
        return PairingResult.failure(lastError!);
      }
      final deviceName = _cleanName(name) ??
          await _prefsString(prefsDeviceName) ??
          await _deviceName();

      final saved = await _patch(
        'pairings/$code/devices/$installId',
        {
          'adminKey': _s(secret),
          'installId': _s(installId),
          'name': _s(deviceName),
          'joinedAt': _ts(DateTime.now().toUtc()),
        },
      );
      if (saved == null) {
        lastError = 'Не удалось сохранить устройство';
        return PairingResult.failure(lastError!);
      }
      if (!_ok(saved)) {
        lastError = 'Не удалось сохранить устройство (${saved.statusCode})';
        return PairingResult.failure(lastError!);
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefsPairedCode, code);
        await prefs.setString(prefsPairedInstallId, desktopInstallId);
        await prefs.setString(prefsPairedName, desktopName);
        await prefs.setString(prefsDeviceName, deviceName);
      } catch (_) {
        // Код всё равно рабочий: prefs нужен только для sendOrder, и его
        // можно восстановить повторным join.
      }

      return PairingResult.success(
        code: code,
        desktopInstallId: desktopInstallId,
        desktopName: desktopName,
      );
    } catch (_) {
      lastError = 'Не удалось подключиться по коду';
      return PairingResult.failure(lastError!);
    }
  }

  /// Отправляет заказ компьютеру, к которому подключён телефон.
  ///
  /// Возвращает id созданного документа `incoming/{orderId}` или `null` при
  /// ошибке (текст в [lastError]). Заказ уходит строкой `orderJson` и
  /// человекочитаемой сводкой `summary`.
  static Future<String?> sendOrder(OrderProject project, {String? name}) async {
    lastError = null;
    if (isTest) return 'test-order';
    try {
      var desktopInstallId = await _prefsString(prefsPairedInstallId) ?? '';
      if (desktopInstallId.isEmpty) {
        final paired = await _prefsString(prefsPairedCode);
        if (paired != null && isValidCode(paired)) {
          desktopInstallId = await _refreshPairedDesktop(paired) ?? '';
        }
      }
      if (desktopInstallId.isEmpty) {
        lastError = 'Сначала подключитесь к компьютеру по коду';
        return null;
      }
      final fromInstallId = await _installId() ?? '';
      final fromName = _cleanName(name) ??
          await _prefsString(prefsDeviceName) ??
          await _deviceName();
      final orderJson = orderToJsonString(project);
      final summary = summaryText(project);
      final orderId = _newOrderId();
      final now = DateTime.now().toUtc();

      final response = await _patch(
        'installations/$desktopInstallId/incoming/$orderId',
        {
          'adminKey': _s(secret),
          'orderId': _s(orderId),
          'fromInstallId': _s(fromInstallId),
          'fromName': _s(fromName),
          'createdAt': _ts(now),
          'status': _s('new'),
          'orderJson': _s(orderJson),
          'summary': _s(summary),
        },
      );
      if (response == null) {
        lastError ??= 'Нет связи с сервером';
        return null;
      }
      if (!_ok(response)) {
        lastError = 'Не удалось отправить заказ (${response.statusCode})';
        return null;
      }
      return orderId;
    } catch (_) {
      lastError = 'Не удалось отправить заказ';
      return null;
    }
  }

  /// Входящие заказы этого компьютера (свежие сверху).
  ///
  /// Читает `installations/{installId}/incoming` через `runQuery` с фильтром
  /// `adminKey == secret`. Битые документы (нет валидного `orderJson`)
  /// пропускаются. В тестах возвращает пустой список.
  /// Подключённые телефоны этого компьютера.
  static Future<List<PairingDevice>> listDevices() async {
    if (isTest) return const [];
    final code = await currentCode();
    if (code == null) return const [];
    try {
      final response = await http
          .post(
            Uri.parse('$_base/pairings/${code.code}:runQuery?key=$apiKey'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'structuredQuery': {
                'from': [
                  {'collectionId': 'devices'},
                ],
                'where': {
                  'fieldFilter': {
                    'field': {'fieldPath': 'adminKey'},
                    'op': 'EQUAL',
                    'value': {'stringValue': secret},
                  },
                },
              },
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return const [];
      final rows = jsonDecode(response.body);
      if (rows is! List) return const [];
      final result = <PairingDevice>[];
      for (final row in rows) {
        final document = row is Map ? row['document'] : null;
        if (document is! Map) continue;
        final fields = document['fields'];
        if (fields is! Map) continue;
        String text(String key) => '${fields[key]?['stringValue'] ?? ''}';
        final joined = DateTime.tryParse(text('joinedAt'));
        result.add(
          PairingDevice(
            installId: text('installId'),
            name: text('name'),
            joinedAt: joined ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<IncomingOrder>> listIncoming() async {
    lastError = null;
    if (isTest) return const [];
    try {
      final installId = await _installId();
      if (installId == null) {
        lastError = 'Не удалось определить установку';
        return const [];
      }
      final uri = Uri.parse(
        '$_base/installations/$installId:runQuery',
      ).replace(queryParameters: {'key': apiKey});
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'structuredQuery': {
                'from': [
                  {'collectionId': 'incoming'},
                ],
                'where': {
                  'fieldFilter': {
                    'field': {'fieldPath': 'adminKey'},
                    'op': 'EQUAL',
                    'value': {'stringValue': secret},
                  },
                },
                'limit': incomingLimit,
              },
            }),
          )
          .timeout(timeout);
      if (!_ok(response)) {
        lastError = 'Не удалось получить заказы (${response.statusCode})';
        return const [];
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return const [];
      final result = <IncomingOrder>[];
      for (final row in decoded) {
        if (row is! Map) continue;
        final document = row['document'];
        if (document is! Map) continue;
        try {
          final order = incomingFromDocument(
            document.cast<String, dynamic>(),
          );
          if (order != null) result.add(order);
        } catch (_) {
          // Один битый документ не должен ломать весь список.
        }
      }
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return result;
    } catch (_) {
      lastError = 'Не удалось получить заказы';
      return const [];
    }
  }

  /// Помечает входящий заказ импортированным (`status: imported`).
  static Future<bool> markImported(String id) async {
    lastError = null;
    if (isTest) return false;
    final orderId = id.trim();
    if (!_validOrderId(orderId)) {
      lastError = 'Неверный номер заказа';
      return false;
    }
    try {
      final installId = await _installId();
      if (installId == null) {
        lastError = 'Не удалось определить установку';
        return false;
      }
      final response = await _patch(
        'installations/$installId/incoming/$orderId',
        {
          'adminKey': _s(secret),
          'status': _s('imported'),
          'importedAt': _ts(DateTime.now().toUtc()),
        },
        mask: const ['status', 'importedAt'],
      );
      if (response == null) {
        lastError ??= 'Нет связи с сервером';
        return false;
      }
      if (!_ok(response)) {
        lastError = 'Не удалось отметить заказ (${response.statusCode})';
        return false;
      }
      return true;
    } catch (_) {
      lastError = 'Не удалось отметить заказ';
      return false;
    }
  }

  /// Удаляет входящий заказ.
  static Future<bool> deleteIncoming(String id) async {
    lastError = null;
    if (isTest) return false;
    final orderId = id.trim();
    if (!_validOrderId(orderId)) {
      lastError = 'Неверный номер заказа';
      return false;
    }
    try {
      final installId = await _installId();
      if (installId == null) {
        lastError = 'Не удалось определить установку';
        return false;
      }
      final uri = Uri.parse(
        '$_base/installations/$installId/incoming/$orderId',
      ).replace(queryParameters: {'key': apiKey});
      final response = await http.delete(uri).timeout(timeout);
      if (!_ok(response)) {
        lastError = 'Не удалось удалить заказ (${response.statusCode})';
        return false;
      }
      return true;
    } catch (_) {
      lastError = 'Не удалось удалить заказ';
      return false;
    }
  }

  /// Отключает телефон от компьютера (локально).
  static Future<bool> unpair() async {
    lastError = null;
    if (isTest) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsPairedCode);
      await prefs.remove(prefsPairedInstallId);
      await prefs.remove(prefsPairedName);
      await prefs.remove(prefsDeviceName);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Код компьютера, к которому подключён телефон, из prefs.
  static Future<String?> pairedCode() async {
    final code = await _prefsString(prefsPairedCode);
    return code != null && isValidCode(code) ? code : null;
  }

  /// Имя компьютера, к которому подключён телефон, из prefs.
  static Future<String?> pairedDesktopName() =>
      _prefsString(prefsPairedName);

  // ------------------------------------------------------- внутреннее

  static bool _ok(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  static bool _validOrderId(String id) =>
      id.isNotEmpty && !id.contains('/') && id.length <= 1500;

  static String? _cleanName(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static Random _secureRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static String _windowsLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return '$count окно';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$count окна';
    }
    return '$count окон';
  }

  static double _areaM2(OrderProject project) {
    try {
      final value = CostsSummary(project).productAreaM2;
      if (value.isFinite && value > 0) return value;
    } catch (_) {}
    // Резервный расчёт: габарит полотна. Нужен только для подписи, если
    // геометрия неожиданно не посчиталась.
    var area = 0.0;
    for (final window in project.windows) {
      final width = window.effectiveBottomWidth;
      final height = window.effectiveLeftHeight;
      if (width.isFinite && height.isFinite && width > 0 && height > 0) {
        area += width * height / 1000000;
      }
    }
    return area;
  }

  static String _newOrderId() {
    final rng = _secureRandom();
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final tail = rng.nextInt(0x7fffffff).toRadixString(36).padLeft(6, '0');
    return 'ord-$stamp-$tail';
  }

  /// installId установки: значение Telemetry, а до её инициализации — то же
  /// самое значение из prefs. Ключ общий с телеметрией, поэтому оба сервиса
  /// видят один id.
  static Future<String?> _installId() async {
    final live = Telemetry.installId;
    if (live != null && live.isNotEmpty) return live;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('telemetry_install_id');
      if (saved != null && saved.isNotEmpty) return saved;
      final now = DateTime.now();
      final created =
          'okna-${now.millisecondsSinceEpoch}-${now.microsecond}';
      await prefs.setString('telemetry_install_id', created);
      return created;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _deviceName() async {
    try {
      final info = await device.basicDeviceInfo();
      final hostname = info['hostname'];
      if (hostname is String &&
          hostname.trim().isNotEmpty &&
          hostname != 'browser') {
        return hostname.trim();
      }
      final os = info['os'];
      if (os == 'web') return 'Браузер';
      if (os is String && os.isNotEmpty) return os;
    } catch (_) {}
    return 'Телефон';
  }

  static Future<String?> _prefsString(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveDesktopCode(
    String code,
    DateTime createdAt,
    String desktopName,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsCode, code);
      await prefs.setString(prefsCreatedAt, createdAt.toIso8601String());
      await prefs.setString(prefsDesktopName, desktopName);
    } catch (_) {
      // prefs недоступен — код всё равно создан на сервере.
    }
  }

  static Future<void> _clearDesktopCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsCode);
      await prefs.remove(prefsCreatedAt);
      await prefs.remove(prefsDesktopName);
    } catch (_) {}
  }

  /// Обновляет из Firestore installId/имя компьютера, к которому подключён
  /// телефон. Возвращает installId или `null`.
  static Future<String?> _refreshPairedDesktop(String code) async {
    try {
      final response = await _get('pairings/$code');
      if (response == null || !_ok(response)) return null;
      final document = _decodeDocument(response);
      if (document == null) return null;
      final fields = _fieldsOf(document);
      if (fields['active'] != true) {
        lastError = 'Код компьютера больше не активен';
        return null;
      }
      final installId = _stringOf(fields['desktopInstallId']);
      if (installId.isEmpty) return null;
      final name = _stringOf(fields['desktopName'], 'Компьютер');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefsPairedInstallId, installId);
        await prefs.setString(prefsPairedName, name);
      } catch (_) {}
      return installId;
    } catch (_) {
      return null;
    }
  }

  /// GET документа. `null` — сеть/таймаут.
  static Future<http.Response?> _get(String path) async {
    try {
      final uri = Uri.parse('$_base/$path').replace(
        queryParameters: {'key': apiKey},
      );
      return await http.get(uri).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// PATCH документа. Без [mask] документ перезаписывается целиком, с
  /// [mask] — обновляются только перечисленные поля.
  static Future<http.Response?> _patch(
    String path,
    Map<String, dynamic> fields, {
    List<String>? mask,
  }) async {
    try {
      final query = <String, dynamic>{'key': apiKey};
      if (mask != null && mask.isNotEmpty) {
        query['updateMask.fieldPaths'] = mask;
      }
      final uri =
          Uri.parse('$_base/$path').replace(queryParameters: query);
      return await http
          .patch(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'fields': fields}),
          )
          .timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// Свободен ли код: документа нет или он деактивирован.
  ///
  /// При сетевой ошибке считаем код свободным и пробуем записать — иначе
  /// создание кода падало бы из-за того же сбоя, который всё равно выявит
  /// PATCH.
  static Future<bool> _isCodeFree(String code) async {
    final response = await _get('pairings/$code');
    if (response == null) return true;
    if (response.statusCode == 404) return true;
    if (!_ok(response)) return true;
    final document = _decodeDocument(response);
    if (document == null) return true;
    final fields = _fieldsOf(document);
    return fields['active'] != true;
  }

  static Map<String, dynamic>? _decodeDocument(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?> _fieldsOf(Map<dynamic, dynamic> document) {
    final raw = document['fields'];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        '${entry.key}': _fireValue(entry.value),
    };
  }

  /// Значение Firestore REST → обычное значение Dart.
  static Object? _fireValue(Object? raw) {
    if (raw is! Map) return null;
    if (raw.containsKey('stringValue')) return raw['stringValue'];
    if (raw.containsKey('booleanValue')) return raw['booleanValue'];
    if (raw.containsKey('integerValue')) {
      return int.tryParse('${raw['integerValue']}');
    }
    if (raw.containsKey('doubleValue')) {
      final value = raw['doubleValue'];
      return value is num ? value.toDouble() : double.tryParse('$value');
    }
    if (raw.containsKey('timestampValue')) {
      final value = raw['timestampValue'];
      return value is String ? DateTime.tryParse(value) : null;
    }
    if (raw.containsKey('nullValue')) return null;
    if (raw.containsKey('arrayValue')) {
      final values = raw['arrayValue'];
      if (values is Map) {
        final list = values['values'];
        if (list is List) return [for (final item in list) _fireValue(item)];
      }
      return const [];
    }
    if (raw.containsKey('mapValue')) {
      final map = raw['mapValue'];
      if (map is Map) return _fieldsOf(map);
      return const {};
    }
    return null;
  }

  static String _stringOf(Object? value, [String fallback = '']) =>
      value is String ? value : fallback;

  static DateTime? _dateOf(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, dynamic> _s(String value) => {'stringValue': value};
  static Map<String, dynamic> _b(bool value) => {'booleanValue': value};
  static Map<String, dynamic> _ts(DateTime value) =>
      {'timestampValue': value.toUtc().toIso8601String()};
}

/// Подключённый телефон.
class PairingDevice {
  const PairingDevice({
    required this.installId,
    required this.name,
    required this.joinedAt,
  });

  final String installId;
  final String name;
  final DateTime joinedAt;
}

/// Код компьютера.
class PairingCode {
  const PairingCode({
    required this.code,
    required this.createdAt,
    this.desktopName = '',
    this.active = true,
  });

  /// 6 цифр, ведущие нули значимы.
  final String code;

  final DateTime createdAt;

  /// Имя компьютера, который показывает код.
  final String desktopName;

  final bool active;

  bool get isValid => RegExp(r'^\d{6}$').hasMatch(code);
}

/// Результат подключения телефона к компьютеру.
class PairingResult {
  const PairingResult._({
    required this.ok,
    this.code = '',
    this.desktopInstallId = '',
    this.desktopName = '',
    this.message = '',
  });

  factory PairingResult.success({
    required String code,
    required String desktopInstallId,
    required String desktopName,
  }) =>
      PairingResult._(
        ok: true,
        code: code,
        desktopInstallId: desktopInstallId,
        desktopName: desktopName,
      );

  factory PairingResult.failure(String message) =>
      PairingResult._(ok: false, message: message);

  final bool ok;
  final String code;
  final String desktopInstallId;
  final String desktopName;

  /// Причина отказа (для UI).
  final String message;
}

/// Входящий заказ с телефона замерщика.
class IncomingOrder {
  const IncomingOrder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.project,
    required this.summary,
    this.fromInstallId = '',
    this.status = 'new',
  });

  /// id документа `incoming/{id}` — нужен для [Pairing.markImported] и
  /// [Pairing.deleteIncoming].
  final String id;

  /// Имя отправителя (телефона/замерщика).
  final String name;

  final DateTime createdAt;

  final OrderProject project;

  /// Короткая подпись: «2 окна · 7,40 м²».
  final String summary;

  /// installId телефона, с которого пришёл заказ.
  final String fromInstallId;

  /// `new` или `imported`.
  final String status;
}
