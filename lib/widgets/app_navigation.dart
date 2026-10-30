import 'package:flutter/material.dart';

import '../config/app_section.dart';
import '../theme/app_tokens.dart';

/// Левая навигация на широком экране.
///
/// Ширину можно менять перетаскиванием правой кромки, а кнопка в шапке
/// сворачивает рейл до иконок. Состояние хранит вызывающий экран.
class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({
    super.key,
    required this.section,
    required this.onSelect,
    required this.version,
    this.collapsed = false,
    this.width = 236,
    this.onToggle,
    this.onWidthChanged,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSelect;
  final String version;
  final bool collapsed;
  final double width;
  final VoidCallback? onToggle;
  final ValueChanged<double>? onWidthChanged;

  @override
  Widget build(BuildContext context) {
    final actualWidth = collapsed ? 78.0 : width;
    return Stack(
      children: [
        Container(
          width: actualWidth,
          color: AppTokens.paper,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: collapsed
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                _header(context),
                if (!collapsed)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'ПРОИЗВОДСТВО',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: AppTokens.faint,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final item in AppSection.values)
                  _RailItem(
                    item: item,
                    selected: section == item,
                    collapsed: collapsed,
                    onTap: () => onSelect(item),
                  ),
                const Spacer(),
                _footer(),
              ],
            ),
          ),
        ),
        if (!collapsed && onWidthChanged != null)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 8,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                key: const Key('nav-rail-resize'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) =>
                    onWidthChanged!(width + details.delta.dx),
                child: Container(
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: Container(
                    width: 2,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTokens.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 10 : 20,
        22,
        collapsed ? 10 : 10,
        22,
      ),
      child: collapsed
          ? Column(
              children: [
                _brandMark(),
                const SizedBox(height: 10),
                _toggleButton(),
              ],
            )
          : Row(
              children: [
                _brandMark(),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'МЯГКИЕ ОКНА',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: AppTokens.copper,
                        ),
                      ),
                      Text(
                        'Excl',
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          color: AppTokens.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                _toggleButton(),
              ],
            ),
    );
  }

  Widget _brandMark() => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      gradient: AppTokens.copperGradient,
      borderRadius: BorderRadius.circular(13),
      boxShadow: [
        BoxShadow(
          color: AppTokens.copper.withValues(alpha: 0.28),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: const Icon(Icons.blinds, color: Colors.white, size: 23),
  );

  Widget _toggleButton() {
    if (onToggle == null) return const SizedBox.shrink();
    return IconButton(
      key: const Key('nav-rail-toggle'),
      tooltip: collapsed ? 'Развернуть меню' : 'Свернуть меню',
      visualDensity: VisualDensity.compact,
      onPressed: onToggle,
      icon: Icon(
        collapsed ? Icons.chevron_right : Icons.chevron_left,
        size: 18,
        color: AppTokens.faint,
      ),
    );
  }

  Widget _footer() {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Tooltip(
          message: 'Локальная база SQLite · версия $version',
          child: const Icon(
            Icons.storage_outlined,
            size: 18,
            color: AppTokens.green,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.cream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTokens.lineSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.storage_outlined, size: 15, color: AppTokens.green),
                SizedBox(width: 6),
                Text(
                  'Локальная база',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.inkSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'SQLite · версия $version',
              style: const TextStyle(fontSize: 9.5, color: AppTokens.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final AppSection item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 10 : 10,
        vertical: 2,
      ),
      child: Material(
        color: selected ? AppTokens.copperSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 12 : 11,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppTokens.copper.withValues(alpha: 0.28)
                    : Colors.transparent,
              ),
            ),
            child: collapsed
                ? Center(
                    child: Icon(
                      item.icon,
                      size: 20,
                      color: selected ? AppTokens.copper : AppTokens.muted,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        item.icon,
                        size: 19,
                        color: selected ? AppTokens.copper : AppTokens.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: selected
                                    ? AppTokens.ink
                                    : AppTokens.inkSoft,
                              ),
                            ),
                            Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: AppTokens.faint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: AppTokens.copper,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
    if (!collapsed) return content;
    return Tooltip(message: '${item.label} · ${item.subtitle}', child: content);
  }
}

/// Нижняя навигация на телефоне и планшете.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.section,
    required this.onSelect,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: section.index,
      onDestinationSelected: (index) => onSelect(AppSection.values[index]),
      height: 68,
      backgroundColor: AppTokens.paper,
      indicatorColor: AppTokens.copperSoft,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        for (final item in AppSection.values)
          NavigationDestination(
            icon: Icon(item.icon, size: 22),
            selectedIcon: Icon(item.icon, size: 22, color: AppTokens.copper),
            label: item.label,
          ),
      ],
    );
  }
}
