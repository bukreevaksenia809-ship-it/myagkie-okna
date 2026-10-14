import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'models/order_project.dart';
import 'models/window_geometry.dart';
import 'models/price_list.dart';
import 'models/window_params.dart';
import 'services/order_storage.dart';
import 'services/tech_checks.dart';
import 'services/pdf_export.dart';
import 'services/roll_plan.dart';
import 'widgets/costs_sheet.dart';
import 'widgets/cut_sheet.dart';
import 'widgets/estimate_sheet.dart';
import 'widgets/drawing_sheet.dart';
import 'widgets/orders_panel.dart';
import 'widgets/price_panel.dart';
import 'widgets/params_panel.dart';
import 'widgets/roll_sheet.dart';
import 'widgets/tech_card_sheet.dart';

/// Версия сборки — видна в интерфейсе, чтобы понимать, какая версия открыта.
const String kAppVersion = '1.1.0';

void main() {
  runApp(const SoftWindowApp());
}

class SoftWindowApp extends StatelessWidget {
  const SoftWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мягкие окна',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B62C4)),
      ),
      locale: const Locale('ru'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru'), Locale('en')],
      home: const BuilderScreen(),
    );
  }
}

/// Что показано на листе.
enum SheetTab { drawing, cut, roll, costs, estimate, techCard }

class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key});

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  OrderProject _project = const OrderProject();
  PriceList _prices = const PriceList.defaults();
  SheetTab _tab = SheetTab.drawing;
  List<SavedOrder> _orders = const [];
  bool _ordersBusy = false;
  final GlobalKey _sheetKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();
  final TransformationController _zoom = TransformationController();
  double _zoomLevel = 1;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tab = _tabFromUrl();
    _zoom.addListener(_onZoomChanged);
    _refreshOrders();
  }

  /// Вкладку можно открыть ссылкой: ?tab=costs или ?tab=roll.
  SheetTab _tabFromUrl() {
    final requested = Uri.base.queryParameters['tab']?.toLowerCase();
    return switch (requested) {
      'roll' || 'raskladka' => SheetTab.roll,
      'costs' || 'rashody' => SheetTab.costs,
      'cut' || 'raskroy' => SheetTab.cut,
      'estimate' || 'smeta' => SheetTab.estimate,
      'tech' || 'tehkarta' || 'techcard' => SheetTab.techCard,
      _ => SheetTab.drawing,
    };
  }

  @override
  void dispose() {
    _zoom.removeListener(_onZoomChanged);
    _zoom.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final scale = _zoom.value.getMaxScaleOnAxis();
    if ((scale - _zoomLevel).abs() > 0.01) {
      setState(() => _zoomLevel = scale);
    }
  }

  void _updateProject(OrderProject project) => setState(() => _project = project);

  void _reset() => setState(() {
        _project = const OrderProject();
        _zoom.value = Matrix4.identity();
      });

  // ------------------------------------------------------------------ заказы

  Future<void> _refreshOrders() async {
    setState(() => _ordersBusy = true);
    final orders = await listSavedOrders();
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _ordersBusy = false;
    });
  }

  Future<void> _saveOrder() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _ordersBusy = true);
    try {
      final saved = await saveOrder(_project);
      await _refreshOrders();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Заказ сохранён: ${saved.title}'),
          duration: const Duration(seconds: 10),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _ordersBusy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось сохранить заказ: $error')),
      );
    }
  }

  Future<void> _openOrder(SavedOrder order) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _ordersBusy = true);
    try {
      final project = await loadOrder(order);
      if (!mounted) return;
      setState(() {
        _project = project;
        _ordersBusy = false;
      });
      _resetZoom();
      messenger.showSnackBar(
        SnackBar(content: Text('Заказ открыт: ${order.title}')),
      );
    } catch (error) {
      if (mounted) setState(() => _ordersBusy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось открыть заказ: $error')),
      );
    }
  }

  Future<void> _deleteOrder(SavedOrder order) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _ordersBusy = true);
    try {
      await deleteOrder(order);
      await _refreshOrders();
      messenger.showSnackBar(
        SnackBar(content: Text('Файл заказа удалён: ${order.title}')),
      );
    } catch (error) {
      if (mounted) setState(() => _ordersBusy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось удалить заказ: $error')),
      );
    }
  }

  // ----------------------------------------------------------------- масштаб

  /// Приближение/отдаление вокруг центра области просмотра.
  void _zoomTo(double target) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(900, 600);
    final value = target.clamp(0.15, 5.0);
    _zoom.value = Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..scaleByDouble(value, value, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
    setState(() => _zoomLevel = value);
  }

  void _zoomBy(double factor) => _zoomTo(_zoomLevel * factor);

  void _resetZoom() {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    final viewport = box?.size ?? const Size(900, 600);
    final sheetSize = _explicitSheetSize(viewport);
    if (sheetSize == null) {
      _zoom.value = Matrix4.identity();
      setState(() => _zoomLevel = 1);
      return;
    }
    // Длинный лист показываем по ширине окна — дальше прокрутка.
    final scale = (viewport.width / sheetSize.width).clamp(0.15, 1.0);
    _zoom.value = Matrix4.identity()..scaleByDouble(scale, scale, 1, 1);
    setState(() => _zoomLevel = scale);
  }

  // -------------------------------------------------------------- экспорт

  /// Явный размер листа (длинные листы: подробный чертёж и ведомость).
  Size? _explicitSheetSize(Size viewport) => switch (_tab) {
        SheetTab.drawing =>
          DrawingSheet.detailedSheetSize(_project, viewport),
        SheetTab.roll => null,
        SheetTab.cut => CutSheet.sheetSize(_project, viewport),
        SheetTab.costs => CostsSheet.sheetSize(_project, viewport),
        SheetTab.estimate => EstimateSheet.sheetSize(_project, viewport),
        SheetTab.techCard => TechCardSheet.sheetSize(_project, viewport),
      };

  /// Границы, по которым можно резать PDF, не разрывая окно.
  List<double>? _safeBreakFractions(Size viewport) => _tab == SheetTab.drawing
      ? DrawingSheet.safeBreakFractions(_project, viewport)
      : null;

  String get _sheetPrefix => switch (_tab) {
        SheetTab.drawing => 'Чертёж',
        SheetTab.roll => 'Раскладка',
        SheetTab.cut => 'Раскрой',
        SheetTab.costs => 'Расходы',
        SheetTab.estimate => 'Смета',
        SheetTab.techCard => 'Техкарта',
      };

  Future<void> _exportPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    final params = _project.selected;
    final viewport = _viewportSize();
    setState(() => _exporting = true);
    try {
      final saved = await exportSheetToPdf(
        captureKey: _sheetKey,
        params: params,
        namePrefix: _sheetPrefix,
        safeBreakFractions: _safeBreakFractions(viewport),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Сохранено: ${saved.destination}'),
          duration: const Duration(seconds: 10),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось сохранить PDF: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printSheet() async {
    final messenger = ScaffoldMessenger.of(context);
    final params = _project.selected;
    final viewport = _viewportSize();
    setState(() => _exporting = true);
    try {
      final printed = await printSheet(
        captureKey: _sheetKey,
        params: params,
        jobName: '$_sheetPrefix ${params.drawingNumber}',
        safeBreakFractions: _safeBreakFractions(viewport),
      );
      if (!printed) {
        messenger.showSnackBar(const SnackBar(content: Text('Печать отменена')));
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось напечатать: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Раздел «Технолог»: производственные проверки, дополняющие валидацию.
  Widget _techSection() {
    final windowChecks = techChecksFor(_project.selected);
    final orderChecks = techChecksForOrder(_project);
    final checks = [...orderChecks, ...windowChecks];
    final blocking = hasBlockingTechChecks(checks);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: blocking ? const Color(0xFFE0A0A0) : const Color(0xFFD9E0EA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ТЕХНОЛОГ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: blocking
                        ? const Color(0xFFB03A3A)
                        : const Color(0xFF66748A),
                  ),
                ),
              ),
              Text(
                checks.isEmpty ? 'замечаний нет' : 'замечаний: ${checks.length}',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A93A0)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (checks.isEmpty)
            const Text(
              'Размеры, шаг люверсов, ширина окантовки и спецэлементы '
              'выглядят по технологии.',
              style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
            )
          else
            for (final check in checks.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (check.severity) {
                        TechSeverity.error => Icons.error_outline,
                        TechSeverity.warning => Icons.warning_amber_outlined,
                        TechSeverity.info => Icons.info_outline,
                      },
                      size: 15,
                      color: switch (check.severity) {
                        TechSeverity.error => const Color(0xFFB03A3A),
                        TechSeverity.warning => const Color(0xFFB07A1E),
                        TechSeverity.info => const Color(0xFF4A7BA7),
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            check.title,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2B3440),
                            ),
                          ),
                          Text(
                            check.recommendation.isEmpty
                                ? check.explanation
                                : '${check.explanation} ${check.recommendation}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              height: 1.25,
                              color: Color(0xFF66748A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Size _viewportSize() {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size ?? const Size(1400, 900);
  }

  @override
  Widget build(BuildContext context) {
    final selectedSpec = WindowSpec.of(_project.selected);
    final issues = validateParams(_project.selected);
    final rollPlans = buildRollPlans(_project);
    final narrow = MediaQuery.sizeOf(context).width < 1000;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мягкие окна — чертежи, раскрой, раскладка'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (narrow) ...[
            IconButton(
              tooltip: 'Сохранить PDF',
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf),
            ),
            IconButton(
              tooltip: 'Печать',
              onPressed: _printSheet,
              icon: const Icon(Icons.print_outlined),
            ),
            IconButton(
              tooltip: 'Сбросить',
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: Text('Сохранить ${_sheetPrefix.toLowerCase()}'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _printSheet,
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Печать'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Сбросить'),
            ),
          ],
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panel = SizedBox(
            width: narrow ? null : 420,
            child: ParamsPanel(
              project: _project,
              issues: issues,
              onChanged: _updateProject,
              onReset: _reset,
              pricesSection: PricePanel(
                prices: _prices,
                onChanged: (prices) => setState(() => _prices = prices),
              ),
              techSection: _techSection(),
              ordersSection: OrdersPanel(
                orders: _orders,
                folderPath: ordersFolderDescription(),
                busy: _ordersBusy,
                onSave: _saveOrder,
                onRefresh: _refreshOrders,
                onOpen: _openOrder,
                onDelete: _deleteOrder,
              ),
            ),
          );
          final sheetArea = Column(
            children: [
              _toolbar(),
              const Divider(height: 1, thickness: 1),
              Expanded(child: _sheetViewport()),
            ],
          );

          if (!narrow) {
            return Row(
              children: [
                panel,
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: sheetArea),
              ],
            );
          }
          // Узкий экран (планшет, телефон, окно браузера): панель сверху.
          return Column(
            children: [
              SizedBox(
                height: constraints.maxHeight * 0.42,
                child: panel,
              ),
              const Divider(height: 1, thickness: 1),
              Expanded(child: sheetArea),
            ],
          );
        },
      ),
      bottomNavigationBar: _StatusBar(
        project: _project,
        selectedSpec: selectedSpec,
        rollPlans: rollPlans,
      ),
    );
  }

  Widget _sheetViewport() {
    return Container(
      key: _viewportKey,
      color: const Color(0xFFDDE3EC),
      child: LayoutBuilder(
        builder: (context, viewport) {
          final sheet = switch (_tab) {
            SheetTab.drawing => DrawingSheet(
                project: _project,
                captureKey: _sheetKey,
              ),
            SheetTab.roll => RollSheet(
                project: _project,
                captureKey: _sheetKey,
              ),
            SheetTab.cut => CutSheet(
                project: _project,
                captureKey: _sheetKey,
              ),
            SheetTab.costs => CostsSheet(
                project: _project,
                captureKey: _sheetKey,
              ),
            SheetTab.estimate => EstimateSheet(
                project: _project,
                prices: _prices,
                captureKey: _sheetKey,
              ),
            SheetTab.techCard => TechCardSheet(
                project: _project,
                captureKey: _sheetKey,
              ),
          };
          final explicit = _explicitSheetSize(viewport.biggest);

          return InteractiveViewer(
            transformationController: _zoom,
            constrained: explicit == null,
            minScale: 0.15,
            maxScale: 5,
            boundaryMargin: const EdgeInsets.all(800),
            child: explicit == null
                ? sheet
                : SizedBox(
                    width: explicit.width,
                    height: explicit.height,
                    child: sheet,
                  ),
          );
        },
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      color: const Color(0xFFF2F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SegmentedButton<SheetTab>(
              segments: const [
                ButtonSegment(
                  value: SheetTab.drawing,
                  icon: Icon(Icons.architecture, size: 18),
                  label: Text('Чертёж'),
                ),
                ButtonSegment(
                  value: SheetTab.cut,
                  icon: Icon(Icons.crop_square_outlined, size: 18),
                  label: Text('Раскрой'),
                ),
                ButtonSegment(
                  value: SheetTab.roll,
                  icon: Icon(Icons.view_week_outlined, size: 18),
                  label: Text('Рулон'),
                ),
                ButtonSegment(
                  value: SheetTab.costs,
                  icon: Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text('Расходы'),
                ),
                ButtonSegment(
                  value: SheetTab.estimate,
                  icon: Icon(Icons.request_quote_outlined, size: 18),
                  label: Text('Смета'),
                ),
                ButtonSegment(
                  value: SheetTab.techCard,
                  icon: Icon(Icons.assignment_outlined, size: 18),
                  label: Text('Техкарта'),
                ),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _tab = selection.first);
                _resetZoom();
              },
            ),
            const SizedBox(width: 12),
            SegmentedButton<SheetMode>(
              segments: const [
                ButtonSegment(
                  value: SheetMode.single,
                  label: Text('Одно окно'),
                ),
                ButtonSegment(
                  value: SheetMode.grid,
                  label: Text('Все окна'),
                ),
              ],
              selected: {_project.sheetMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _updateProject(
                _project.setSheetMode(selection.first),
              ),
            ),
            if (_tab == SheetTab.drawing &&
                _project.sheetMode == SheetMode.grid &&
                _project.isMultiWindow) ...[
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _project.gridColumns,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Авто, окон в ряду')),
                  DropdownMenuItem(value: 1, child: Text('1 в ряд (подробно)')),
                  DropdownMenuItem(value: 2, child: Text('2 в ряд')),
                  DropdownMenuItem(value: 3, child: Text('3 в ряд')),
                  DropdownMenuItem(value: 4, child: Text('4 в ряд')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _updateProject(_project.setGridColumns(value));
                  }
                },
              ),
            ],
            const SizedBox(width: 24),
            IconButton(
              tooltip: 'Отдалить',
              onPressed: () => _zoomBy(1 / 1.25),
              icon: const Icon(Icons.zoom_out),
            ),
            Text(
              '${(_zoomLevel * 100).round()} %',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF41506A),
              ),
            ),
            IconButton(
              tooltip: 'Приблизить',
              onPressed: () => _zoomBy(1.25),
              icon: const Icon(Icons.zoom_in),
            ),
            IconButton(
              tooltip: 'Показать лист целиком',
              onPressed: _resetZoom,
              icon: const Icon(Icons.fit_screen, size: 20),
            ),
            const SizedBox(width: 8),
            const Tooltip(
              message: 'Колесо мыши или трекпад — масштаб, '
                  'перетаскивание — сдвиг листа',
              child:
                  Icon(Icons.help_outline, size: 18, color: Color(0xFF7C8798)),
            ),
            const SizedBox(width: 6),
            Text(
              'v$kAppVersion',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8A93A0)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.project,
    required this.selectedSpec,
    required this.rollPlans,
  });

  final OrderProject project;
  final WindowSpec selectedSpec;
  final List<RollPlan> rollPlans;

  @override
  Widget build(BuildContext context) {
    final specs = [for (final window in project.windows) WindowSpec.of(window)];
    final totalFilmArea =
        specs.fold<double>(0, (sum, spec) => sum + spec.filmAreaM2);
    final totalProductArea =
        specs.fold<double>(0, (sum, spec) => sum + spec.productAreaM2);
    final totalEyelets =
        specs.fold<int>(0, (sum, spec) => sum + spec.eyeletCount);
    final consumption = <double, double>{};
    for (final spec in specs) {
      spec.edgeConsumption.forEach((roll, length) {
        consumption[roll] = (consumption[roll] ?? 0) + length;
      });
    }
    final consumptionText = (consumption.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((entry) => '${edgeBandLabel(entry.key)}: ${formatCm(entry.value)} см')
        .join(' · ');

    return Container(
      height: 64,
      color: const Color(0xFF111C2B),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _stat('Окон в заказе', '${project.windowCount} шт'),
          _stat(
            'Выбранное окно',
            '№${project.selectedIndex + 1} · '
                '${formatMm(selectedSpec.geometry.spanX)}×'
                '${formatMm(selectedSpec.geometry.overallHeight)} мм',
          ),
          _stat('Площадь изделий', '${formatMeters(totalProductArea)} м²'),
          _stat('Плёнка: площадь', '${formatMeters(totalFilmArea)} м²'),
          _stat('Люверсы', 'всего $totalEyelets шт'),
          _stat('Расход окантовки', consumptionText),
          _stat(
            'Рулоны (материал)',
            rollPlans.isEmpty
                ? '—'
                : rollPlans
                    .map((plan) =>
                        '${plan.material.label.split(' ').first} '
                        '${formatMm(plan.rollWidth)}×'
                        '${formatMm(plan.layout.requiredLength)}')
                    .join(' · '),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              letterSpacing: 0.6,
              color: Color(0xFF8FA3BC),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
