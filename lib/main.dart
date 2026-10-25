import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'models/order_project.dart';
import 'models/window_geometry.dart';
import 'models/price_list.dart';
import 'models/window_params.dart';
import 'services/order_storage.dart';
import 'services/client_report_pdf.dart';
import 'widgets/client_report_dialog.dart';
import 'widgets/pricebook_switcher.dart';
import 'services/company_branding.dart';
import 'services/license.dart';
import 'services/telemetry.dart';
import 'widgets/license_dialog.dart';
import 'services/label_settings.dart';
import 'services/tech_checks.dart';
import 'services/pdf_export.dart';
import 'services/roll_plan.dart';
import 'widgets/calculator.dart';
import 'widgets/company_dialog.dart';
import 'widgets/costs_sheet.dart';
import 'widgets/docs/docs_tab.dart';
import 'widgets/cut_sheet.dart';
import 'widgets/estimate_sheet.dart';
import 'widgets/drawing_sheet.dart';
import 'widgets/orders_panel.dart';
import 'widgets/params_panel.dart';
import 'widgets/print_dialog.dart';
import 'widgets/roll_sheet.dart';
import 'widgets/tech_card_sheet.dart';

/// Версия сборки — видна в интерфейсе, чтобы понимать, какая версия открыта.
const String kAppVersion = '1.3.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Единицы показа читаем до первой сборки: если заказчик выбрал см,
  // приложение не мигнёт миллиметрами.
  await DisplayUnits.load();
  // Размеры подписей читаем там же: листы должны открыться с выбранными
  // кеглями, а не мигнуть стандартными.
  await LabelSettings.load();
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
enum SheetTab { drawing, cut, roll, costs, docs, estimate, techCard }

/// «1 лист», «2 листа», «5 листов» — для имени задания печати.
String _sheetsWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) return 'лист';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'листа';
  return 'листов';
}

/// Заказ в верхнем списке: имя и проект с окнами.
class _OrderDraft {
  _OrderDraft({required this.name, required this.project});

  final String name;
  final OrderProject project;

  _OrderDraft copyWith({String? name, OrderProject? project}) =>
      _OrderDraft(name: name ?? this.name, project: project ?? this.project);
}

class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key});

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  /// Заказы сверху: у каждого своё имя и свои окна. Активный — [_orderIndex].
  List<_OrderDraft> _drafts = [
    _OrderDraft(name: 'Заказ 1', project: const OrderProject()),
  ];
  int _orderIndex = 0;

  /// Проект активного заказа.
  OrderProject get _project => _drafts[_orderIndex].project;

  PriceList _prices = const PriceList.defaults();

  /// Второй прайс — дилерский. Начинается с клиентских цен, дальше его
  /// можно менять отдельно; смета дилера считается по нему.
  PriceList _dealerPrices = const PriceList.defaults();

  /// Какая смета открыта: клиентская или дилерская.
  bool _dealerEstimate = false;

  LicenseState? _license;

  /// Горизонтальная прокрутка панели листов: стрелки слева и справа.
  final ScrollController _toolbarScroll = ScrollController();
  SheetTab _tab = SheetTab.drawing;
  List<SavedOrder> _orders = const [];
  bool _ordersBusy = false;
  final GlobalKey _sheetKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();
  final TransformationController _zoom = TransformationController();
  double _zoomLevel = 1;
  bool _exporting = false;

  /// Прогресс подготовки печати: пока не null, поверх экрана видна завеса.
  PrintProgress? _printProgress;

  @override
  void initState() {
    super.initState();
    _tab = _tabFromUrl();
    CompanyBranding.load();
    CompanyBranding.current.addListener(_onBrandingChanged);
    _zoom.addListener(_onZoomChanged);
    DisplayUnits.current.addListener(_onUnitsChanged);
    LabelSettings.current.addListener(_onLabelSettingsChanged);
    _refreshOrders();
    _initTelemetry();
    _initLicense();
  }

  /// Активация: без ключа показываем блокирующий диалог.
  Future<void> _initLicense() async {
    final state = await LicenseService.check();
    if (!mounted) return;
    setState(() => _license = state);
    if (state.active) return;
    final result = await showLicenseDialog(
      context,
      blocking: true,
      initial: state,
    );
    if (!mounted) return;
    if (result != null) setState(() => _license = result);
  }

  Future<void> _openLicense() async {
    final result = await showLicenseDialog(
      context,
      blocking: _license?.active == false,
      initial: _license,
    );
    if (mounted && result != null) setState(() => _license = result);
  }

  /// Пульс на сервер и проверка обновлений — в фоне, без блокировки окна.
  Future<void> _initTelemetry() async {
    await Telemetry.init(project: _project, version: kAppVersion);
    final update = await Telemetry.checkUpdate();
    if (!mounted || update == null) return;
    if (_isNewerVersion(update.version, kAppVersion)) _showUpdate(update);
  }

  bool _isNewerVersion(String remote, String local) {
    List<int> parts(String value) => [
      for (final chunk in value.split('.'))
        int.tryParse(chunk.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
    ];
    final a = parts(remote);
    final b = parts(local);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  Future<void> _showUpdate(AppUpdate update) async {
    if (update.autoUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Обновление до ${update.version}: приложение перезапустится…')),
      );
      await Telemetry.applyUpdate(update);
      return;
    }
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Доступна версия ${update.version}'),
        content: Text(
          update.notes.trim().isEmpty
              ? 'Обновить приложение сейчас?'
              : update.notes,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Позже'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.system_update_alt, size: 18),
            label: const Text('Обновить'),
          ),
        ],
      ),
    );
    if (apply != true) return;
    final ok = await Telemetry.applyUpdate(update);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновиться. Ссылка: ${update.url}')),
      );
    }
  }

  /// Переключатель мм/см перерисовывает всё приложение: подписи на панели,
  /// чертеже и табличных листах считаются в build, а не хранятся в модели.
  void _onUnitsChanged() {
    if (mounted) setState(() {});
  }

  /// Новый размер подписи перерисовывает листы: пейнтеры получают снимок
  /// [LabelSettings] при сборке и сравнивают его в shouldRepaint.
  void _onLabelSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// Реквизиты компании/логотип перерисовывают листы (смета, чертёж).
  void _onBrandingChanged() {
    if (mounted) setState(() {});
  }

  /// Вкладку можно открыть ссылкой: ?tab=costs или ?tab=roll.
  SheetTab _tabFromUrl() {
    final requested = Uri.base.queryParameters['tab']?.toLowerCase();
    return switch (requested) {
      'roll' || 'raskladka' => SheetTab.roll,
      'costs' || 'rashody' => SheetTab.costs,
      'docs' || 'dokumenty' || 'documentation' => SheetTab.docs,
      'cut' || 'raskroy' => SheetTab.cut,
      'estimate' || 'smeta' => SheetTab.estimate,
      'tech' || 'tehkarta' || 'techcard' => SheetTab.techCard,
      _ => SheetTab.drawing,
    };
  }

  @override
  void dispose() {
    _toolbarScroll.dispose();
    CompanyBranding.current.removeListener(_onBrandingChanged);
    _zoom.removeListener(_onZoomChanged);
    DisplayUnits.current.removeListener(_onUnitsChanged);
    LabelSettings.current.removeListener(_onLabelSettingsChanged);
    _zoom.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final scale = _zoom.value.getMaxScaleOnAxis();
    if ((scale - _zoomLevel).abs() > 0.01) {
      setState(() => _zoomLevel = scale);
    }
  }

  void _updateProject(OrderProject project) {
    setState(() {
      _drafts[_orderIndex] = _drafts[_orderIndex].copyWith(project: project);
    });
    Telemetry.projectChanged(project, kAppVersion);
  }

  void _reset() => setState(() {
    _drafts[_orderIndex] = _drafts[_orderIndex].copyWith(
      project: const OrderProject(),
    );
    _zoom.value = Matrix4.identity();
  });

  // ---------------------------------------------------------- верхние заказы

  void _selectOrderDraft(int index) {
    if (index < 0 || index >= _drafts.length) return;
    setState(() => _orderIndex = index);
    _resetZoom();
  }

  Future<void> _createOrderDraft() async {
    final name = await _askOrderName(
      title: 'Новый заказ',
      initial: 'Заказ ${_drafts.length + 1}',
    );
    if (name == null || !mounted) return;
    setState(() {
      _drafts = [
        ..._drafts,
        _OrderDraft(name: name, project: const OrderProject()),
      ];
      _orderIndex = _drafts.length - 1;
    });
    _resetZoom();
  }

  Future<void> _renameOrderDraft(int index) async {
    if (index < 0 || index >= _drafts.length) return;
    final name = await _askOrderName(
      title: 'Переименовать заказ',
      initial: _drafts[index].name,
    );
    if (name == null || !mounted) return;
    setState(() {
      _drafts[index] = _drafts[index].copyWith(name: name);
    });
  }

  void _deleteOrderDraft(int index) {
    if (_drafts.length <= 1 || index < 0 || index >= _drafts.length) return;
    final next = [..._drafts]..removeAt(index);
    var selected = _orderIndex;
    if (index < selected) selected--;
    if (selected >= next.length) selected = next.length - 1;
    setState(() {
      _drafts = next;
      _orderIndex = selected;
    });
  }

  Future<String?> _askOrderName({
    required String title,
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('order-name-field'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название заказа',
            hintText: 'Например: Дача, Беседка, Кухня',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('save-order-name'),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    // Диалог закрывается анимацией: поле ещё перерисовывается несколько
    // кадров, поэтому controller нельзя освобождать сразу.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    final trimmed = result?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

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
      final saved = await saveOrder(_project, name: _drafts[_orderIndex].name);
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
        _drafts = [
          ..._drafts,
          _OrderDraft(name: order.title, project: project),
        ];
        _orderIndex = _drafts.length - 1;
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
    SheetTab.drawing => DrawingSheet.detailedSheetSize(_project, viewport),
    SheetTab.roll => null,
    SheetTab.cut => CutSheet.sheetSize(_project, viewport),
    SheetTab.costs => CostsSheet.sheetSize(_project, viewport),
    // Документация — не лист: у неё своя A4-страница в редакторе.
    SheetTab.docs => null,
    SheetTab.estimate => EstimateSheet.sheetSize(
      _project,
      viewport,
      prices: _prices,
    ),
    SheetTab.techCard => TechCardSheet.sheetSize(_project, viewport),
  };

  /// Границы, по которым можно резать PDF, не разрывая окно.
  List<double>? _safeBreakFractions(Size viewport) =>
      _safeBreakFractionsFor(_tab, viewport);

  /// То же, но для конкретного листа: при печати пачки вкладки переключаются.
  List<double>? _safeBreakFractionsFor(SheetTab tab, Size viewport) =>
      switch (tab) {
        SheetTab.drawing => DrawingSheet.safeBreakFractions(_project, viewport),
        // Смета и раскрой — всегда один лист A4: режем ровно по его краям,
        // чтобы даже погрешность пропорций не добавила вторую страницу.
        SheetTab.estimate || SheetTab.cut => const [0.0, 1.0],
        _ => null,
      };

  /// Формат страницы PDF для вкладки.
  ///
  /// Чертёж, раскрой и смета — A4 в портретной ориентации: каждый лист
  /// построен ровно в пропорциях A4 и печатается без масштабирования.
  /// Остальным табличным листам (расходы, техкарта) нужна широкая A3.
  SheetPageFormat _pageFormatFor(SheetTab tab) => switch (tab) {
    // Чертёж, раскрой и смета — ровно A4: каждый лист теперь один A4.
    SheetTab.drawing ||
    SheetTab.cut ||
    SheetTab.estimate => SheetPageFormat.a4Portrait,
    _ => SheetPageFormat.a3LandscapeAuto,
  };

  String get _sheetPrefix => switch (_tab) {
    SheetTab.drawing => 'Чертёж',
    SheetTab.roll => 'Раскладка',
    SheetTab.cut => 'Раскрой',
    SheetTab.costs => 'Расходы',
    SheetTab.docs => 'Документация',
    SheetTab.estimate =>
      _dealerEstimate ? 'Смета дилер' : 'Смета',
    SheetTab.techCard => 'Техкарта',
  };

  /// «Сохранить отчёт для клиента»: альбомный PDF с обложкой и страницами
  /// окон (чертёж + раскрой), в отличие от производственных листов.
  Future<void> _exportClientReport() async {
    if (_exporting) return;
    // Сначала данные заказчика — прямо здесь, не в панели программы.
    final info = await showClientReportDialog(
      context,
      project: _project,
      company: CompanyBranding.current.value,
    );
    if (info == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final saved = await saveClientReport(
        project: _project,
        prices: _prices,
        company: CompanyBranding.current.value,
        info: info,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Отчёт для клиента: ${saved.destination}')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось сохранить отчёт: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    // Пока идёт другой экспорт, второй раз не запускаем.
    if (_exporting) return;
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
        pageFormat: _pageFormatFor(_tab),
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

  /// Печать: сначала спрашиваем, какие листы печатать, затем печатаем
  /// выбранные одним заданием.
  Future<void> _printSheet() async {
    // Пока идёт предыдущая печать, повторный запуск не принимаем.
    if (_exporting) return;
    final selected = await showPrintSheetDialog(
      context,
      current: _tab,
      isMultiWindow: _project.isMultiWindow,
    );
    // Отмена диалога или пустой выбор — просто ничего не делаем.
    if (!mounted || selected == null || selected.isEmpty) return;
    await _printSelected(selected);
  }

  /// Печатает выбранные листы одним заданием.
  ///
  /// Лист снимается прямо с экрана, поэтому вкладки переключаются по очереди:
  /// после каждого переключения ждём кадр и только потом снимаем лист.
  ///
  /// PDF собирается ИНКРЕМЕНТАЛЬНО: [SheetPdfBuilder] создаёт документ один
  /// раз, и каждый лист добавляет в него свои страницы сразу после съёмки.
  /// Список готовых картинок при этом нигде не копится: одновременно живут
  /// только снимок текущего листа и одна его страница.
  ///
  /// Управление регулярно отдаётся браузеру ([_yieldToBrowser] между листами
  /// и страницами, плюс `enableEventLoopBalancing` внутри `save()`): в вебе
  /// сборка PDF идёт в главном потоке, и без этого вкладка «зависает».
  /// Пока идёт съёмка, поверх экрана видно, какой лист готовится сейчас.
  ///
  /// В конце возвращаем исходную вкладку и масштаб, что бы ни случилось.
  Future<void> _printSelected(List<SheetTab> tabs) async {
    final messenger = ScaffoldMessenger.of(context);
    final params = _project.selected;
    final viewport = _viewportSize();
    final previousTab = _tab;
    final previousZoom = _zoom.value.clone();
    final previousZoomLevel = _zoomLevel;
    final total = tabs.length;
    // Один текущий лист печатаем как раньше: без переключения вкладок
    // и без сброса масштаба — экран не дёргается.
    final singleCurrent = tabs.length == 1 && tabs.single == previousTab;
    final jobName = singleCurrent
        ? '$_sheetPrefix ${params.drawingNumber}'
        : 'Мягкие окна — $total ${_sheetsWord(total)}';

    setState(() => _exporting = true);
    try {
      final builder = SheetPdfBuilder(title: jobName);

      var index = 0;
      for (final tab in tabs) {
        if (!mounted) return;
        index++;
        _setPrintProgress(
          PrintProgress(
            current: index,
            total: total,
            title: sheetTabTitle(tab),
            pagesReady: builder.pageCount,
          ),
        );
        if (!singleCurrent) {
          setState(() => _tab = tab);
          // Лист показываем как обычно: снимок не зависит от масштаба,
          // но так лист строится в своих штатных размерах.
          _resetZoom();
          await WidgetsBinding.instance.endOfFrame;
          // Запас на дорисовку: длинный лист строится не за один кадр.
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (!mounted) return;
        }
        await builder.addSheet(
          captureKey: _sheetKey,
          safeBreakFractions: _safeBreakFractionsFor(tab, viewport),
          // Чертёж — на A4, табличные листы — на широкой странице A3.
          pageFormat: _pageFormatFor(tab),
          onPageAdded: (pagesInSheet) async {
            // После каждой страницы обновляем счётчик и отдаём управление,
            // чтобы браузер успел перерисовать окно прогресса.
            _setPrintProgress(
              PrintProgress(
                current: index,
                total: total,
                title: sheetTabTitle(tab),
                pagesReady: builder.pageCount,
              ),
            );
            await _yieldToBrowser();
          },
        );
        await _yieldToBrowser();
      }

      if (!mounted) return;
      if (builder.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Нечего печатать: листы не построены')),
        );
        return;
      }

      // Самая тяжёлая часть — сборка PDF. Управление отдаётся и здесь:
      // в браузере `save()` идёт в главном потоке целиком.
      _setPrintProgress(
        PrintProgress(
          current: total,
          total: total,
          title: sheetTabTitle(tabs.last),
          pagesReady: builder.pageCount,
          assembling: true,
        ),
      );
      await _yieldToBrowser();
      final bytes = await builder.save();
      // Документ отпущен: в памяти остались только готовые байты PDF.
      final printed = await printPdfBytes(bytes: bytes, jobName: jobName);
      if (!printed) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Печать отменена')),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось напечатать: $error')),
      );
    } finally {
      // Что бы ни случилось, убираем завесу и возвращаем исходную вкладку
      // и масштаб.
      if (mounted) {
        setState(() {
          _printProgress = null;
          _tab = previousTab;
          _zoomLevel = previousZoomLevel;
          _exporting = false;
        });
        _zoom.value = previousZoom;
      }
    }
  }

  void _setPrintProgress(PrintProgress value) {
    if (!mounted) return;
    setState(() => _printProgress = value);
  }

  /// Отдаёт управление браузеру: он успевает перерисовать страницу, и
  /// вкладка не выглядит зависшей. На десктопе это просто короткая пауза.
  Future<void> _yieldToBrowser() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 16));
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
                checks.isEmpty
                    ? 'замечаний нет'
                    : 'замечаний: ${checks.length}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF8A93A0),
                ),
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
          IconButton(
            key: const Key('license-appbar'),
            tooltip: _license?.active == false
                ? 'Лицензия не активирована'
                : 'Лицензия',
            onPressed: _openLicense,
            icon: Icon(
              _license?.active == false
                  ? Icons.key_off_outlined
                  : Icons.verified_user_outlined,
            ),
          ),
          // Компания на листах — всегда под рукой: настройка глобальная, и
          // искать её внизу длинной панели неудобно.
          IconButton(
            key: const Key('company-appbar'),
            tooltip: 'Компания на листах: реквизиты и логотип',
            onPressed: () => showCompanyDialog(context),
            icon: const Icon(Icons.business_outlined),
          ),
          if (_tab == SheetTab.docs)
            // У документации свои кнопки PDF/печати и своего набора листов:
            // снимать её как лист чертежа нельзя.
            const SizedBox.shrink()
          else if (_exporting)
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
              key: const Key('client-report-narrow'),
              tooltip: 'Отчёт для клиента',
              onPressed: _exportClientReport,
              icon: const Icon(Icons.badge_outlined),
            ),
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
            OutlinedButton.icon(
              key: const Key('client-report'),
              onPressed: _exportClientReport,
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('Отчёт клиенту'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: Text(
                _tab == SheetTab.drawing
                    ? 'Чертёж для производства'
                    : 'Сохранить ${_sheetPrefix.toLowerCase()}',
              ),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final panel = SizedBox(
                width: narrow ? null : 420,
                child: ParamsPanel(
                  project: _project,
                  issues: issues,
                  onChanged: _updateProject,
                  onReset: _reset,
                  prices: _prices,
                  orderOverviews: [
                    for (var i = 0; i < _drafts.length; i++)
                      OrderOverview(
                        name: _drafts[i].name,
                        windowCount: _drafts[i].project.windowCount,
                      ),
                  ],
                  selectedOrderIndex: _orderIndex,
                  onSelectOrder: _selectOrderDraft,
                  onCreateOrder: _createOrderDraft,
                  onRenameOrder: _renameOrderDraft,
                  onDeleteOrder: _deleteOrderDraft,
                  pricesSection: PricebookSwitcher(
                    client: _prices,
                    dealer: _dealerPrices,
                    materials: _project.materialsInOrder,
                    onClientChanged: (prices) =>
                        setState(() => _prices = prices),
                    onDealerChanged: (prices) =>
                        setState(() => _dealerPrices = prices),
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
                  SizedBox(height: constraints.maxHeight * 0.42, child: panel),
                  const Divider(height: 1, thickness: 1),
                  Expanded(child: sheetArea),
                ],
              );
            },
          ),
          // Пока готовятся листы, поверх экрана видно прогресс: в браузере
          // съёмка и сборка PDF идут в главном потоке и занимают секунды.
          if (_printProgress != null)
            PrintProgressOverlay(progress: _printProgress!),
        ],
      ),
      // Калькулятор — только на вкладке «Чертёж». Кнопка живёт поверх
      // области листа, но вне captureKey: в снимок, PDF и печать не попадает
      // и не перехватывает жесты панорамирования.
      floatingActionButton: _tab == SheetTab.drawing
          ? FloatingActionButton(
              key: const Key('calculator-fab'),
              tooltip: 'Калькулятор',
              onPressed: () => showCalculator(context),
              child: const Icon(Icons.calculate_outlined),
            )
          : null,
      bottomNavigationBar: _StatusBar(
        project: _project,
        selectedSpec: selectedSpec,
        rollPlans: rollPlans,
      ),
    );
  }

  Widget _sheetViewport() {
    // Документация — редактор документов, а не лист чертежа: масштабирование
    // и панорамирование ей не нужны, поэтому InteractiveViewer не оборачивает.
    if (_tab == SheetTab.docs) {
      return DocsTab(project: _project, prices: _prices);
    }
    return Container(
      key: _viewportKey,
      color: const Color(0xFFDDE3EC),
      child: LayoutBuilder(
        builder: (context, viewport) {
          final sheet = switch (_tab) {
            SheetTab.drawing => DrawingSheet(
              project: _project,
              captureKey: _sheetKey,
              company: CompanyBranding.current.value,
              // Люверсы можно перетаскивать мышкой прямо по чертежу.
              onParamsChanged: (params) =>
                  _updateProject(_project.updateSelected(params)),
            ),
            SheetTab.roll => RollSheet(
              project: _project,
              captureKey: _sheetKey,
            ),
            SheetTab.cut => CutSheet(project: _project, captureKey: _sheetKey),
            SheetTab.costs => CostsSheet(
              project: _project,
              captureKey: _sheetKey,
            ),
            SheetTab.docs => DocsTab(project: _project, prices: _prices),
            SheetTab.estimate => EstimateSheet(
              project: _project,
              prices: _dealerEstimate ? _dealerPrices : _prices,
              captureKey: _sheetKey,
              company: CompanyBranding.current.value,
              title: _dealerEstimate ? 'Смета (дилер)' : 'Смета на заказ',
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            key: const Key('toolbar-scroll-left'),
            tooltip: 'Прокрутить влево',
            visualDensity: VisualDensity.compact,
            onPressed: () => _scrollToolbar(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _toolbarScroll,
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
                  value: SheetTab.docs,
                  icon: Icon(Icons.description_outlined, size: 18),
                  label: Text('Документация'),
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
                ButtonSegment(value: SheetMode.grid, label: Text('Все окна')),
              ],
              selected: {_project.sheetMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  _updateProject(_project.setSheetMode(selection.first)),
            ),
            if (_tab == SheetTab.estimate) ...[
              const SizedBox(width: 12),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Клиент')),
                  ButtonSegment(value: true, label: Text('Дилер')),
                ],
                selected: {_dealerEstimate},
                onSelectionChanged: (selection) =>
                    setState(() => _dealerEstimate = selection.first),
              ),
            ],
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
              message:
                  'Колесо мыши или трекпад — масштаб, '
                  'перетаскивание — сдвиг листа. Люверс можно перетащить '
                  'мышкой вдоль линии окантовки',
              child: Icon(
                Icons.help_outline,
                size: 18,
                color: Color(0xFF7C8798),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'v$kAppVersion',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8A93A0)),
            ),
          ],
              ),
            ),
          ),
          IconButton(
            key: const Key('toolbar-scroll-right'),
            tooltip: 'Прокрутить вправо',
            visualDensity: VisualDensity.compact,
            onPressed: () => _scrollToolbar(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  /// Прокрутка строки листов стрелками: на узком экране вкладки иначе
  /// уходят за край и до них не добраться.
  void _scrollToolbar(double direction) {
    if (!_toolbarScroll.hasClients) return;
    final position = _toolbarScroll.position;
    final target = (position.pixels + direction * 320).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _toolbarScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
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
    // Плёнка в заказе — заготовки к раскрою, то есть с припуском на раскрой.
    final totalFilmArea = specs.fold<double>(
      0,
      (sum, spec) => sum + spec.filmCutAreaM2,
    );
    final totalProductArea = specs.fold<double>(
      0,
      (sum, spec) => sum + spec.productAreaM2,
    );
    final totalEyelets = specs.fold<int>(
      0,
      (sum, spec) => sum + spec.eyeletCount,
    );
    final consumption = <double, double>{};
    for (final spec in specs) {
      spec.edgeConsumption.forEach((roll, length) {
        consumption[roll] = (consumption[roll] ?? 0) + length;
      });
    }
    final consumptionText =
        (consumption.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map(
              (entry) =>
                  '${edgeBandLabel(entry.key)}: ${formatMm(entry.value)} ${unitSuffix()}',
            )
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
                '${formatMm(selectedSpec.geometry.overallHeight)} ${unitSuffix()}',
          ),
          _stat('Площадь изделий', '${formatMeters(totalProductArea)} м²'),
          _stat('Плёнка: заготовки', '${formatMeters(totalFilmArea)} м²'),
          _stat('Люверсы', 'всего $totalEyelets шт'),
          _stat('Расход окантовки', consumptionText),
          _stat(
            'Рулоны (материал)',
            rollPlans.isEmpty
                ? '—'
                : rollPlans
                      .map(
                        (plan) =>
                            '${plan.material.label.split(' ').first} '
                            '${formatMm(plan.rollWidth)}×'
                            '${formatMm(plan.layout.requiredLength)}',
                      )
                      .join(' · '),
          ),
          const SizedBox(width: 200, child: _UnitsSwitch()),
          const SizedBox(width: 8),
          const _LabelSettingsButton(),
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

/// Переключатель единиц внизу экрана: «Единицы: мм · см».
///
/// Стоит в нижней строке рядом с итогами, поэтому всегда на виду. Значение
/// хранится в [DisplayUnits] (shared_preferences), переключение мгновенно
/// перерисовывает панель, чертёж и все листы. Ввод в полях остаётся в мм.
class _UnitsSwitch extends StatelessWidget {
  const _UnitsSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LengthUnit>(
      valueListenable: DisplayUnits.current,
      builder: (context, unit, _) {
        return Row(
          key: const Key('length-unit-switch'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Единицы:',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF8FA3BC)),
            ),
            const SizedBox(width: 6),
            _UnitButton(
              key: const Key('unit-mm'),
              label: 'мм',
              selected: unit == LengthUnit.mm,
              onTap: () => DisplayUnits.setUnit(LengthUnit.mm),
            ),
            const SizedBox(width: 4),
            _UnitButton(
              key: const Key('unit-cm'),
              label: 'см',
              selected: unit == LengthUnit.cm,
              onTap: () => DisplayUnits.setUnit(LengthUnit.cm),
            ),
          ],
        );
      },
    );
  }
}

class _UnitButton extends StatelessWidget {
  const _UnitButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFF1D2C40),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? Colors.white : const Color(0xFF44566D),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF111C2B) : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Кнопка «Настройки подписей» в нижней строке рядом с единицами мм/см.
///
/// Заказчик: «нужно добавить настройку регулирования размеров всех подписей
/// (для каждой отдельно)». Кнопка открывает диалог с восемью типами подписей;
/// значения хранятся в shared_preferences и сразу перерисовывают листы.
class _LabelSettingsButton extends StatelessWidget {
  const _LabelSettingsButton();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const Key('label-settings-button'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => const _LabelSettingsDialog(),
      ),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      icon: const Icon(Icons.text_fields, size: 16),
      label: const Text('Настройки подписей'),
    );
  }
}

/// Диалог размеров всех восьми типов подписей, 5…24 pt.
class _LabelSettingsDialog extends StatefulWidget {
  const _LabelSettingsDialog();

  @override
  State<_LabelSettingsDialog> createState() => _LabelSettingsDialogState();
}

class _LabelSettingsDialogState extends State<_LabelSettingsDialog> {
  late LabelSettings _settings = LabelSettings.value;

  void _set(LabelKind kind, double value) {
    // setSize сразу меняет notifier, поэтому листы перерисовываются под
    // диалогом, а сохранение в shared_preferences идёт следом.
    LabelSettings.setSize(kind, value);
    setState(() => _settings = LabelSettings.value);
  }

  Future<void> _reset() async {
    await LabelSettings.resetToDefaults();
    if (!mounted) return;
    setState(() => _settings = LabelSettings.value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Настройки подписей'),
      content: SizedBox(
        width: 520,
        height: 680,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Размер каждой группы подписей настраивается отдельно, '
              'от 5 до 24 pt. Значения сохраняются и применяются на всех '
              'листах: чертёж, раскрой, расходы, смета, техкарта.',
              style: TextStyle(fontSize: 12, color: Color(0xFF66748A)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: LabelKind.values.length,
                separatorBuilder: (_, _) => const Divider(height: 10),
                itemBuilder: (context, index) {
                  final kind = LabelKind.values[index];
                  final value = _settings.ptFor(kind);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              kind.label,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${value.toStringAsFixed(1).replaceAll('.', ',')} pt',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF0B62C4),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        key: Key('label-size-${kind.name}'),
                        min: LabelSettings.minPt,
                        max: LabelSettings.maxPt,
                        divisions: 38,
                        value: value.clamp(
                          LabelSettings.minPt,
                          LabelSettings.maxPt,
                        ),
                        label: kind.label,
                        onChanged: (next) => _set(kind, next),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('label-settings-reset'),
          onPressed: _reset,
          child: const Text('Сбросить к стандартным'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
