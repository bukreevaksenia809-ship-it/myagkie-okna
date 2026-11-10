// Хранилище импортированных DOCX-шаблонов.
//
// Отдельный ключ shared_preferences, чтобы не раздувать библиотеку документов
// заказа и не ломать её формат. Блоки хранятся в JSON, сырые байты DOCX — нет:
// шаблон нужен для вставки в заказ, а не для повторной распаковки.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'docx_import.dart';

class ImportedDocxStore {
  ImportedDocxStore({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  static const String storageKey = 'soft_window_drawer_docx_templates_v1';

  final Future<SharedPreferences> _preferences;

  /// Все шаблоны, новые сверху. Битый JSON — пустой список, без падения.
  Future<List<ImportedDocxTemplate>> load() async {
    try {
      final prefs = await _preferences;
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <ImportedDocxTemplate>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          result.add(
            ImportedDocxTemplate.fromJson(item.cast<String, dynamic>()),
          );
        } catch (_) {
          // Один битый шаблон не должен прятать остальные.
        }
      }
      result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(List<ImportedDocxTemplate> templates) async {
    try {
      final prefs = await _preferences;
      await prefs.setString(
        storageKey,
        jsonEncode([for (final template in templates) template.toJson()]),
      );
    } catch (_) {}
  }

  /// Добавляет или заменяет шаблон по id и возвращает новый список.
  Future<List<ImportedDocxTemplate>> upsert(
    ImportedDocxTemplate template,
  ) async {
    final current = await load();
    final next = [
      for (final item in current)
        if (item.id != template.id) item,
      template,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await saveAll(next);
    return next;
  }

  Future<List<ImportedDocxTemplate>> rename(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return load();
    final current = await load();
    final next = [
      for (final item in current)
        if (item.id == id)
          item.copyWith(title: trimmed, updatedAt: DateTime.now())
        else
          item,
    ];
    await saveAll(next);
    return next;
  }

  /// Копия шаблона: тот же документ под новым названием и id.
  Future<List<ImportedDocxTemplate>> duplicate(String id) async {
    final current = await load();
    final source = current.where((item) => item.id == id).firstOrNull;
    if (source == null) return current;
    final now = DateTime.now();
    final copy = ImportedDocxTemplate(
      id: 'docx_${now.microsecondsSinceEpoch}',
      title: '${source.title} (копия)',
      fileName: source.fileName,
      importedAt: now,
      updatedAt: now,
      blocks: source.blocks,
      warnings: source.warnings,
      sizeBytes: source.sizeBytes,
    );
    return upsert(copy);
  }

  Future<List<ImportedDocxTemplate>> remove(String id) async {
    final current = await load();
    final next = current.where((item) => item.id != id).toList();
    await saveAll(next);
    return next;
  }
}
