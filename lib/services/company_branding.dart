
import 'package:flutter/foundation.dart';

import '../models/document.dart';
import 'document_store.dart';

/// Реквизиты компании и логотип для листов (смета, чертёж).
///
/// Хранится отдельно от заказа: заполняется один раз в настройках и
/// переиспользуется на всех листах. Логотип лежит в хранилище ассетов
/// (файл на десктопе / отдельный ключ в браузере), в JSON — только ссылка.
@immutable
class CompanyBrandingState {
  const CompanyBrandingState({
    this.details = const CompanyDetails(),
    this.logo,
    this.showOnSheets = false,
  });

  final CompanyDetails details;
  final Uint8List? logo;
  final bool showOnSheets;

  bool get hasDetails =>
      details.name.trim().isNotEmpty ||
      details.inn.trim().isNotEmpty ||
      details.phone.trim().isNotEmpty;

  /// Показывать блок на листах: тумблер включён и есть что показать.
  bool get isVisible => showOnSheets && (hasDetails || logo != null);

  /// Подпись под названием компании: «ИНН … · тел. …».
  String get contactLine {
    final parts = <String>[
      if (details.inn.trim().isNotEmpty) 'ИНН ${details.inn.trim()}',
      if (details.ogrn.trim().isNotEmpty) 'ОГРН ${details.ogrn.trim()}',
      if (details.phone.trim().isNotEmpty) 'тел. ${details.phone.trim()}',
      if (details.address.trim().isNotEmpty) details.address.trim(),
    ];
    return parts.join(' · ');
  }

  CompanyBrandingState copyWith({
    CompanyDetails? details,
    Uint8List? logo,
    bool clearLogo = false,
    bool? showOnSheets,
  }) =>
      CompanyBrandingState(
        details: details ?? this.details,
        logo: clearLogo ? null : (logo ?? this.logo),
        showOnSheets: showOnSheets ?? this.showOnSheets,
      );
}

/// Глобальные настройки компании: загрузка, сохранение, тумблер показа.
class CompanyBranding {
  CompanyBranding._();

  static final ValueNotifier<CompanyBrandingState> current =
      ValueNotifier<CompanyBrandingState>(const CompanyBrandingState());

  static DocumentStore? _store;
  static bool _loaded = false;

  static DocumentStore get _documentStore => _store ??= DocumentStore();

  /// Читает реквизиты, логотип и флаг показа из хранилища.
  static Future<void> load({DocumentStore? store, bool force = false}) async {
    if (_loaded && !force) return;
    _store = store ?? _store ?? DocumentStore();
    final details = await _documentStore.loadCompany();
    final logo = await _documentStore.readAsset(details.logoAssetRef);
    final show = await _documentStore.loadCompanyOnSheets();
    _loaded = true;
    current.value = CompanyBrandingState(
      details: details,
      logo: logo,
      showOnSheets: show,
    );
  }

  /// Включает/выключает показ компании на листах.
  static Future<void> setShowOnSheets(bool value) async {
    await _documentStore.saveCompanyOnSheets(value);
    current.value = current.value.copyWith(showOnSheets: value);
  }

  /// Сохраняет реквизиты (без картинки).
  static Future<void> saveDetails(CompanyDetails details) async {
    await _documentStore.saveCompany(details);
    current.value = current.value.copyWith(details: details);
  }

  /// Загружает логотип из файла на диске (десктоп).
  ///
  /// Возвращает false, если платформа не даёт прочитать файл (браузер).
  static Future<bool> importLogoFromPath(String path) async {
    final bytes = await _documentStore.readLocalFile(path);
    if (bytes == null || bytes.isEmpty) return false;
    final ref = await _documentStore.putAsset(_logoFileName(path), bytes);
    // Старый файл больше не нужен — удаляем, чтобы не копился мусор.
    final previous = current.value.details.logoAssetRef;
    if (previous.isNotEmpty && previous != ref) {
      await _documentStore.deleteAsset(previous);
    }
    final details = current.value.details.copyWith(logoAssetRef: ref);
    await _documentStore.saveCompany(details);
    current.value = current.value.copyWith(details: details, logo: bytes);
    return true;
  }

  /// Ставит логотип из байтов (например, вставленный из буфера/тестов).
  static Future<void> setLogoBytes(
    Uint8List bytes, {
    String fileName = 'company_logo.png',
  }) async {
    final ref = await _documentStore.putAsset(fileName, bytes);
    final details = current.value.details.copyWith(logoAssetRef: ref);
    await _documentStore.saveCompany(details);
    current.value = current.value.copyWith(details: details, logo: bytes);
  }

  /// Убирает логотип с листов и из хранилища.
  static Future<void> removeLogo() async {
    final previous = current.value.details.logoAssetRef;
    if (previous.isNotEmpty) await _documentStore.deleteAsset(previous);
    final details = current.value.details.copyWith(logoAssetRef: '');
    await _documentStore.saveCompany(details);
    current.value = current.value.copyWith(
      details: details,
      clearLogo: true,
    );
  }

  static String _logoFileName(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    return name.isEmpty ? 'company_logo.png' : name;
  }

  /// Для тестов: сбросить кеш и подставить готовое состояние.
  @visibleForTesting
  static void resetForTests([CompanyBrandingState? state]) {
    _loaded = state != null;
    _store = null;
    current.value = state ?? const CompanyBrandingState();
  }
}
