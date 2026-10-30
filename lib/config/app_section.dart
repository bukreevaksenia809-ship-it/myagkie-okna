import 'package:flutter/material.dart';

/// Разделы приложения в общей навигации.
enum AppSection {
  builder('Конструктор', 'Чертежи и раскрой', Icons.architecture_outlined),
  orders('Заказы', 'Доска производства', Icons.view_kanban_outlined),
  warehouse('Склад', 'Материалы и партии', Icons.inventory_2_outlined),
  documents('Документы', 'Договоры и акты', Icons.description_outlined),
  settings('Настройки', 'Компания и прайсы', Icons.tune);

  const AppSection(this.label, this.subtitle, this.icon);

  final String label;
  final String subtitle;
  final IconData icon;
}
