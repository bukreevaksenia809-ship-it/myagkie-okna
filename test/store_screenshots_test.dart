import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/main.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(() async {
    await loadRealFonts();
    final icon = File(
      '/Users/davidovjr7/Downloads/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icon.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(ByteData.sublistView(icon.readAsBytesSync())),
        );
      await loader.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('скриншоты для RuStore', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const SoftWindowApp()),
    );
    await tester.pumpAndSettle();
    // Показать лист целиком: несколько шагов отдаления.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byIcon(Icons.zoom_out));
      await tester.pumpAndSettle();
    }

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      final bytes = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final file = File('store/ru-store/$name.png')..createSync(recursive: true);
      file.writeAsBytesSync(bytes!);
    }

    final scaffold = tester.firstState<ScaffoldState>(find.byType(Scaffold));
    scaffold.openDrawer();
    await tester.pumpAndSettle();
    await shot('screen-1-settings');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    await shot('screen-2-shapes');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1100));
    await tester.pumpAndSettle();
    await shot('screen-3-edges');

    scaffold.closeDrawer();
    await tester.pumpAndSettle();
  });
}
