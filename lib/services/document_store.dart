// Хранилище документов заказа.
//
// JSON документов (текст, таблицы, ссылки) лежит в shared_preferences на всех
// платформах: так документы переживают перезапуск и в браузере, и на десктопе.
// Байты картинок/подписей/вложений — отдельно, см. document_assets_io.dart и
// document_assets_web.dart: в JSON остаются только ссылки.
//
// Ключ заказа — [documentOrderKey]: сначала номер чертежа, иначе название
// объекта и заказчик. Все документы заказа лежат одной записью в карте
// «ключ заказа → библиотека документов».
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/document.dart';
import '../models/order_project.dart';
import 'document_assets_io.dart'
    if (dart.library.js_interop) 'document_assets_web.dart' as assets;

/// Хранилище документов и ассетов заказа.
class DocumentStore {
  DocumentStore({this.preferences, String? assetsDirectory})
    : _assetsDirectory = assetsDirectory,
      _assets = assets.DocumentAssetBackend(directoryPath: assetsDirectory);

  /// Ключ карты «заказ → библиотека документов».
  static const String librariesKey = 'soft_window_drawer_documents_v1';

  /// Ключ глобальных реквизитов компании.
  static const String companyKey = 'soft_window_drawer_company_v1';

  /// Тумблер «показывать данные компании и логотип на листах».
  static const String companyOnSheetsKey =
      'soft_window_drawer_company_on_sheets_v1';

  /// Готовые настройки (для тестов); null — брать SharedPreferences.
  final SharedPreferences? preferences;
  final String? _assetsDirectory;
  final assets.DocumentAssetBackend _assets;

  Future<SharedPreferences> get _prefs async =>
      preferences ?? await SharedPreferences.getInstance();

  /// Читает документы заказа. Если их ещё нет — пустая библиотека с
  /// реквизитами компании и клиентом из заказа.
  Future<DocumentLibrary> loadLibrary(
    String orderKey, {
    required OrderProject project,
  }) async {
    final prefs = await _prefs;
    final all = _decodeAll(prefs.getString(librariesKey));
    final company = await loadCompany();
    final raw = all[orderKey];
    if (raw is Map) {
      final library = DocumentLibrary.fromJson(raw.cast<String, dynamic>());
      // Компания хранится ещё и глобально: если в старой записи её нет,
      // подставляем актуальные реквизиты.
      return library.company.isEmpty && !company.isEmpty
          ? library.withCompany(company)
          : library;
    }
    return DocumentLibrary.empty(
      orderKey: orderKey,
      company: company,
      customer: CustomerDetails.fromProject(project),
    );
  }

  /// Сохраняет все документы заказа и (заодно) реквизиты компании.
  Future<void> saveLibrary(DocumentLibrary library) async {
    final prefs = await _prefs;
    final all = _decodeAll(prefs.getString(librariesKey));
    all[library.orderKey] = library.toJson();
    await prefs.setString(librariesKey, jsonEncode(all));
    await saveCompany(library.company);
  }

  /// Удаляет документы заказа (для тестов и «начать заново»).
  Future<void> deleteLibrary(String orderKey) async {
    final prefs = await _prefs;
    final all = _decodeAll(prefs.getString(librariesKey));
    if (all.remove(orderKey) != null) {
      await prefs.setString(librariesKey, jsonEncode(all));
    }
  }

  /// Глобальные реквизиты компании.
  Future<bool> loadCompanyOnSheets() async {
    final prefs = await _prefs;
    return prefs.getBool(companyOnSheetsKey) ?? false;
  }

  Future<void> saveCompanyOnSheets(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(companyOnSheetsKey, value);
  }

  Future<CompanyDetails> loadCompany() async {
    final prefs = await _prefs;
    final raw = prefs.getString(companyKey);
    if (raw == null || raw.isEmpty) return const CompanyDetails();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return CompanyDetails.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // Битые реквизиты не должны мешать открыть документы.
    }
    return const CompanyDetails();
  }

  Future<void> saveCompany(CompanyDetails company) async {
    final prefs = await _prefs;
    await prefs.setString(companyKey, jsonEncode(company.toJson()));
  }

  /// Кладёт байты в хранилище ассетов и возвращает ссылку для JSON.
  Future<String> putAsset(String fileName, Uint8List bytes) =>
      _assets.put(fileName, bytes);

  /// Читает ассет по ссылке из JSON.
  Future<Uint8List?> readAsset(String? ref) =>
      ref == null || ref.isEmpty ? Future.value(null) : _assets.read(ref);

  Future<void> deleteAsset(String? ref) async {
    if (ref == null || ref.isEmpty) return;
    await _assets.delete(ref);
  }

  /// Читает файл с диска (десктоп). В браузере — null.
  Future<Uint8List?> readLocalFile(String path) =>
      assets.readLocalFileBytes(path);

  /// Best-effort извлечение текста DOCX (десктоп). В браузере — null.
  Future<String?> extractDocx(Uint8List bytes) => assets.extractDocxText(bytes);

  /// Подпись места хранения ассетов для интерфейса.
  String get assetsDescription =>
      assets.documentAssetsFolderDescription(_assetsDirectory);
}

Map<String, dynamic> _decodeAll(String? raw) {
  if (raw == null || raw.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {
    // Битый JSON — пустая карта: документы откроются с чистого листа.
  }
  return <String, dynamic>{};
}
