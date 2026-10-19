// Регрессия «Ровно»: прямое переключение «низ» → «верх» одним нажатием.
//
// Заказчик: «когда стоит выравнивание по низу — а ты жмёшь выравнивание по
// верху — ничего не происходит. А если нажмёшь на кнопку „нет“ и снова на
// клавишу „верх“ — то выравнивание станет по верху».
//
// Причин оказалось две:
//  1) переключатель был собран на SegmentedButton — он не вызывал обработчик,
//     когда набор выбранных сегментов не менялся (см. level_edge_panel_test);
//  2) даже когда модель менялась, ЧЕРТЁЖ не перерисовывался: в
//     WindowParams.signature не входило поле levelEdge, поэтому
//     WindowDrawingPainter.shouldRepaint возвращал false, и лист оставался
//     прежним. Отсюда и «ничего не происходит» — менялась только галочка.
//
// Здесь проверяем обе половины: модель и координаты углов после ОДНОГО
// нажатия, shouldRepaint пейнтера и фактическую перерисовку листа (сравнение
// PNG до/после). Плюс все шесть пар переходов на окне с разными высотами и
// на окне с разными ширинами.
//
// Запуск: flutter test test/level_edge_switch_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

import 'test_fonts.dart';

/// Панель шириной 420 px с живым состоянием: правки уходят в проект, а
/// сюда же пишем журнал переданных параметров — по нему видно, что панель
/// отдаёт модели именно новое значение, без «залипания».
class _PanelHost extends StatefulWidget {
  const _PanelHost({super.key, required this.initial, required this.log});

  final OrderProject initial;
  final List<WindowParams> log;

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  late OrderProject project = widget.initial;

  OrderProject get current => project;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: ParamsPanel(
            project: project,
            issues: const [],
            onChanged: (value) {
              widget.log.add(value.selected);
              setState(() => project = value);
            },
            onReset: () {},
          ),
        ),
      ),
    );
  }
}

/// Окно с разными высотами: левая 1000, правая 1400, ширины 1200/1200.
/// Ровно тот случай, на котором заказчик видел «ничего не происходит»:
/// при bottom и top углы разные, значит перерисовка обязана быть видна.
const _differentHeights = WindowParams(
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 1000,
  rightHeight: 1400,
  pvcHeightAllowanceEnabled: false,
);

/// Окно с разными ширинами: 1200/1000, высоты 1200/1200.
const _differentWidths = WindowParams(
  bottomWidth: 1200,
  topWidth: 1000,
  leftHeight: 1200,
  rightHeight: 1200,
  pvcHeightAllowanceEnabled: false,
);

/// Окно с разными и ширинами, и высотами — самый злой случай.
const _differentBoth = WindowParams(
  bottomWidth: 1200,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1400,
  pvcHeightAllowanceEnabled: false,
);

/// Ожидаемая горизонтальность кромок для режима «Ровно».
void _expectLevelEdgeGeometry(WindowParams params) {
  final geometry = WindowSpec.of(params).geometry;
  switch (params.levelEdge) {
    case LevelEdge.bottom:
      expect(
        geometry.bottomLeft.dy,
        closeTo(geometry.bottomRight.dy, 1e-9),
        reason: 'низ горизонтален: низ ровно',
      );
    case LevelEdge.top:
      expect(
        geometry.topLeft.dy,
        closeTo(geometry.topRight.dy, 1e-9),
        reason: 'верх горизонтален: верх ровно',
      );
      expect(
        geometry.topLeft.dy,
        closeTo(
          params.leftHeight > params.rightHeight
              ? params.leftHeight
              : params.rightHeight,
          1e-9,
        ),
        reason: 'верх ровно — верх на максимальной высоте',
      );
      expect(
        geometry.maxY,
        closeTo(
          params.leftHeight > params.rightHeight
              ? params.leftHeight
              : params.rightHeight,
          1e-9,
        ),
      );
    case LevelEdge.none:
      // Перепад поделён поровну: обе кромки наклонены на половину разницы.
      final delta = params.rightHeight - params.leftHeight;
      expect(
        geometry.bottomRight.dy - geometry.bottomLeft.dy,
        closeTo(-delta / 2, 1e-9),
      );
      expect(
        geometry.topRight.dy - geometry.topLeft.dy,
        closeTo(delta / 2, 1e-9),
      );
  }
}

void main() {
  setUpAll(loadRealFonts);

  group('модель «Ровно»', () {
    test('copyWith(levelEdge:) действительно пишет поле', () {
      final bottom = _differentHeights;
      expect(bottom.levelEdge, LevelEdge.bottom);
      for (final edge in LevelEdge.values) {
        final copy = bottom.copyWith(levelEdge: edge);
        expect(copy.levelEdge, edge, reason: 'поле записано: ${edge.name}');
        // Остальные размеры не перепутаны.
        expect(copy.bottomWidth, bottom.bottomWidth);
        expect(copy.rightHeight, bottom.rightHeight);
      }
    });

    test('подпись параметров (signature) меняется вместе с «Ровно»', () {
      // По этой подписи WindowDrawingPainter.shouldRepaint решает,
      // перерисовывать ли лист. Если levelEdge в неё не входит, чертёж
      // «залипает» на прежнем режиме — именно баг заказчика.
      final signatures = <String>{
        for (final edge in LevelEdge.values)
          _differentHeights.copyWith(levelEdge: edge).signature,
      };
      expect(
        signatures.length,
        3,
        reason: 'у каждого режима своя подпись — иначе лист не перерисуется',
      );
    });

    test('у direct-переходов низ↔верх разные углы', () {
      final bottom = WindowSpec.of(
        _differentHeights.copyWith(levelEdge: LevelEdge.bottom),
      ).geometry;
      final top = WindowSpec.of(
        _differentHeights.copyWith(levelEdge: LevelEdge.top),
      ).geometry;
      expect(bottom.topLeft.dy, isNot(closeTo(top.topLeft.dy, 1e-9)));
      expect(bottom.bottomLeft.dy, isNot(closeTo(top.bottomLeft.dy, 1e-9)));
      // Правый нижний угол у обоих режимов совпал — перепад снят с левой
      // стороны, поэтому смотреть надо на левые углы и верх.
      expect(bottom.bottomRight.dy, closeTo(top.bottomRight.dy, 1e-9));
      // Низ ровно: правый верх — 1400; верх ровно: правый низ — 0.
      expect(bottom.topRight, const Offset(1200, 1400));
      expect(top.topRight, const Offset(1200, 1400));
      expect(top.bottomRight, const Offset(1200, 0));
      expect(top.topLeft.dy, 1400);
    });
  });

  group('пейнтер замечает смену «Ровно»', () {
    test('shouldRepaint = true, когда меняется только levelEdge', () {
      final bottom = WindowSpec.of(
        _differentHeights.copyWith(levelEdge: LevelEdge.bottom),
      );
      final top = WindowSpec.of(
        _differentHeights.copyWith(levelEdge: LevelEdge.top),
      );
      // Габарит и масштаб у обоих режимов одинаковы — тем важнее, чтобы
      // пейнтер сравнивал именно параметры.
      expect(top.geometry.spanX, closeTo(bottom.geometry.spanX, 1e-9));
      expect(top.geometry.spanY, closeTo(bottom.geometry.spanY, 1e-9));

      // Раскладка у обоих режимов одна и та же (габарит не меняется) —
      // значит, разницу может поймать только сравнение параметров.
      final layout = DrawingLayout(
        size: const Size(900, 700),
        geometry: bottom.geometry,
      );
      final painterBottom = WindowDrawingPainter(
        params: bottom.params,
        layout: layout,
        layers: bottom.layers,
        options: const DrawingOptions(),
      );
      final painterTop = WindowDrawingPainter(
        params: top.params,
        layout: layout,
        layers: top.layers,
        options: const DrawingOptions(),
      );
      expect(
        painterTop.shouldRepaint(painterBottom),
        isTrue,
        reason: 'смена режима «Ровно» обязана перерисовать лист',
      );
    });

    test('shouldRepaint = false для одинаковых параметров', () {
      final spec = WindowSpec.of(_differentHeights);
      final layout = DrawingLayout(
        size: const Size(900, 700),
        geometry: spec.geometry,
      );
      final a = WindowDrawingPainter(
        params: spec.params,
        layout: layout,
        layers: spec.layers,
        options: const DrawingOptions(),
      );
      final b = WindowDrawingPainter(
        params: WindowSpec.of(_differentHeights).params,
        layout: DrawingLayout(
          size: const Size(900, 700),
          geometry: spec.geometry,
        ),
        layers: spec.layers,
        options: const DrawingOptions(),
      );
      expect(b.shouldRepaint(a), isFalse);
    });
  });

  group('панель: одно нажатие', () {
    Future<void> tapMode(WidgetTester tester, LevelEdge edge) async {
      final finder = find.byKey(Key('level-edge-${edge.name}'));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('низ → верх ОДНИМ нажатием: модель и углы', (tester) async {
      tester.view.physicalSize = const Size(420, 7600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final log = <WindowParams>[];
      final hostKey = GlobalKey<_PanelHostState>();
      await tester.pumpWidget(
        _PanelHost(
          key: hostKey,
          initial: const OrderProject(windows: [_differentHeights]),
          log: log,
        ),
      );
      final host = hostKey.currentState!;
      expect(host.current.selected.levelEdge, LevelEdge.bottom);

      // ОДНО нажатие «Верх» — без промежуточного «Нет».
      await tapMode(tester, LevelEdge.top);

      final params = host.current.selected;
      expect(params.levelEdge, LevelEdge.top);
      // Панель отдала в модель именно новое значение — не «залипшее» старое.
      expect(log, isNotEmpty);
      expect(log.last.levelEdge, LevelEdge.top);
      expect(identical(log.last, params), isTrue);

      final geometry = WindowSpec.of(params).geometry;
      expect(geometry.topLeft.dy, 1400);
      expect(geometry.topRight.dy, 1400);
      expect(geometry.bottomLeft.dy, 400);
      expect(geometry.bottomRight.dy, 0);
      _expectLevelEdgeGeometry(params);

      // Галочка переехала на «Верх».
      expect(
        find.descendant(
          of: find.byKey(const Key('level-edge-top')),
          matching: find.byKey(const Key('level-edge-check')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('level-edge-bottom')),
          matching: find.byKey(const Key('level-edge-check')),
        ),
        findsNothing,
      );
    });

    testWidgets('верх → низ ОДНИМ нажатием: модель и углы', (tester) async {
      tester.view.physicalSize = const Size(420, 7600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final log = <WindowParams>[];
      final hostKey = GlobalKey<_PanelHostState>();
      await tester.pumpWidget(
        _PanelHost(
          key: hostKey,
          initial: OrderProject(
            windows: [_differentHeights.copyWith(levelEdge: LevelEdge.top)],
          ),
          log: log,
        ),
      );
      final host = hostKey.currentState!;
      expect(host.current.selected.levelEdge, LevelEdge.top);

      await tapMode(tester, LevelEdge.bottom);

      final params = host.current.selected;
      expect(params.levelEdge, LevelEdge.bottom);
      expect(log.last.levelEdge, LevelEdge.bottom);
      final geometry = WindowSpec.of(params).geometry;
      expect(geometry.bottomLeft.dy, 0);
      expect(geometry.bottomRight.dy, 0);
      expect(geometry.topLeft.dy, 1000);
      expect(geometry.topRight.dy, 1400);
      _expectLevelEdgeGeometry(params);
    });
  });

  group('все шесть переходов одним нажатием', () {
    const pairs = <(LevelEdge, LevelEdge)>[
      (LevelEdge.bottom, LevelEdge.top),
      (LevelEdge.top, LevelEdge.bottom),
      (LevelEdge.bottom, LevelEdge.none),
      (LevelEdge.none, LevelEdge.bottom),
      (LevelEdge.top, LevelEdge.none),
      (LevelEdge.none, LevelEdge.top),
    ];

    Future<void> checkAllPairs(
      WidgetTester tester,
      WindowParams base,
    ) async {
      for (final pair in pairs) {
        final start = base.copyWith(levelEdge: pair.$1);
        final startGeometry = WindowSpec.of(start).geometry;
        final log = <WindowParams>[];
        final key = GlobalKey<_PanelHostState>();
        await tester.pumpWidget(
          _PanelHost(
            key: key,
            initial: OrderProject(windows: [start]),
            log: log,
          ),
        );
        await tester.pumpAndSettle();
        final host = key.currentState!;
        expect(host.current.selected.levelEdge, pair.$1);

        final finder = find.byKey(Key('level-edge-${pair.$2.name}'));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final params = host.current.selected;
        expect(
          params.levelEdge,
          pair.$2,
          reason: '${pair.$1.name} → ${pair.$2.name} одним нажатием',
        );
        expect(
          log.last.levelEdge,
          pair.$2,
          reason: 'панель отдала модели ${pair.$2.name}',
        );
        _expectLevelEdgeGeometry(params);

        final geometry = WindowSpec.of(params).geometry;
        final differs =
            geometry.bottomLeft != startGeometry.bottomLeft ||
            geometry.bottomRight != startGeometry.bottomRight ||
            geometry.topLeft != startGeometry.topLeft ||
            geometry.topRight != startGeometry.topRight;
        // Для одинаковых высот (окно с разными ширинами) координаты углов
        // у режимов совпадают — там проверяем модель и горизонтальность
        // кромок, а не смещение углов.
        if (params.leftHeight != params.rightHeight) {
          expect(
            differs,
            isTrue,
            reason:
                '${pair.$1.name} → ${pair.$2.name}: должны измениться углы',
          );
        }
      }
    }

    testWidgets('окно с разными высотами: 6 направлений', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(420, 7600);
      tester.view.devicePixelRatio = 1;
      await checkAllPairs(tester, _differentHeights);
    });

    testWidgets('окно с разными ширинами: 6 направлений', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(420, 7600);
      tester.view.devicePixelRatio = 1;
      await checkAllPairs(tester, _differentWidths);
    });

    testWidgets('окно с разными ширинами И высотами: 6 направлений', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(420, 7600);
      tester.view.devicePixelRatio = 1;
      await checkAllPairs(tester, _differentBoth);
    });
  });

  // Превью «до/после» для глаз: лист A4 в режимах «Низ» и «Верх».
  // Запуск: flutter test test/level_edge_switch_test.dart
  testWidgets('пишет PNG-превью «Ровно» низ и верх', (tester) async {
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final directory = Directory('build/preview')..createSync(recursive: true);
    for (final edge in const [LevelEdge.bottom, LevelEdge.top]) {
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: DrawingSheet(
              project: OrderProject(
                windows: [_differentHeights.copyWith(levelEdge: edge)],
              ),
              captureKey: captureKey,
              labelFontFamily: testFontFamily,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bytes = await tester.runAsync(() async {
        final boundary = captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final longest = math.max(boundary.size.width, boundary.size.height);
        final ratio = math.min(2.2, 10000 / longest);
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final file = File('${directory.path}/rovno-${edge.name}.png')
        ..writeAsBytesSync(bytes!);
      expect(file.lengthSync(), greaterThan(5000));
      // ignore: avoid_print
      print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
    }
  });

  group('лист чертежа реально перерисовывается', () {
    testWidgets('низ → верх: PNG листа до и после одного нажатия различается', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(
        DrawingSheet.a4Width + 40,
        DrawingSheet.a4Height + 40,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final captureKey = GlobalKey();
      // Тот же StatefulWidget, что и в приложении: правая часть — лист
      // чертежа, снизу им управляет модель. Панель в тесте не нужна —
      // нажатие имитируем сменой модели, как это делает ParamsPanel.
      final hostKey = GlobalKey<_SheetHostState>();
      await tester.pumpWidget(
        _SheetHost(
          key: hostKey,
          captureKey: captureKey,
          initial: const OrderProject(windows: [_differentHeights]),
        ),
      );
      await tester.pumpAndSettle();

      Future<List<int>> snap() async {
        final bytes = await tester.runAsync(() async {
          final boundary = captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });
        return bytes!;
      }

      final pngBefore = await snap();

      // ОДНО нажатие «Верх» — ровно то, что делает заказчик.
      hostKey.currentState!.tapEdge(LevelEdge.top);
      await tester.pumpAndSettle();
      expect(hostKey.currentState!.project.selected.levelEdge, LevelEdge.top);

      final pngAfter = await snap();
      expect(
        pngAfter.length == pngBefore.length && _sameBytes(pngAfter, pngBefore),
        isFalse,
        reason: 'лист чертежа обязан перерисоваться после смены «Ровно»',
      );
    });
  });
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Хост листа чертежа: хранит проект и умеет «нажать» сегмент «Ровно» так
/// же, как это делает панель, — одним изменением модели.
class _SheetHost extends StatefulWidget {
  const _SheetHost({
    super.key,
    required this.captureKey,
    required this.initial,
  });

  final GlobalKey captureKey;
  final OrderProject initial;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  late OrderProject project = widget.initial;

  void tapEdge(LevelEdge edge) {
    setState(() {
      project = project.updateSelected(
        project.selected.copyWith(levelEdge: edge),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: DrawingSheet(
          project: project,
          captureKey: widget.captureKey,
          labelFontFamily: testFontFamily,
        ),
      ),
    );
  }
}
