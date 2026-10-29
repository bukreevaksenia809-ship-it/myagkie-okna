import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/document.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/services/company_branding.dart';
import 'package:soft_window_drawer/services/document_store.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/estimate_sheet.dart';
import 'package:soft_window_drawer/main.dart' as app;
import 'package:soft_window_drawer/widgets/params_panel.dart';

/// Компания на листах: тумблер, реквизиты, логотип, отрисовка на смете и
/// чертеже.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  late Directory temp;
  late DocumentStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('company_branding');
    store = DocumentStore(
      preferences: await SharedPreferences.getInstance(),
      assetsDirectory: temp.path,
    );
    CompanyBranding.resetForTests();
    await CompanyBranding.load(store: store, force: true);
  });

  tearDown(() async {
    CompanyBranding.resetForTests();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('по умолчанию компания на листах выключена', () {
    expect(CompanyBranding.current.value.showOnSheets, isFalse);
    expect(CompanyBranding.current.value.isVisible, isFalse);
  });

  test('тумблер, реквизиты и логотип сохраняются и читаются', () async {
    await CompanyBranding.setShowOnSheets(true);
    await CompanyBranding.saveDetails(
      const CompanyDetails(
        name: 'ООО Мягкие окна',
        inn: '7701234567',
        phone: '+7 999 123-45-67',
      ),
    );
    await CompanyBranding.setLogoBytes(png, fileName: 'logo.png');

    expect(CompanyBranding.current.value.showOnSheets, isTrue);
    expect(CompanyBranding.current.value.hasDetails, isTrue);
    expect(CompanyBranding.current.value.logo, isNotNull);
    expect(CompanyBranding.current.value.details.logoAssetRef, isNotEmpty);
    expect(CompanyBranding.current.value.isVisible, isTrue);

    // Повторная загрузка из хранилища даёт то же самое.
    await CompanyBranding.load(store: store, force: true);
    final restored = CompanyBranding.current.value;
    expect(restored.showOnSheets, isTrue);
    expect(restored.details.name, 'ООО Мягкие окна');
    expect(restored.details.inn, '7701234567');
    expect(restored.logo, isNotNull);

    await CompanyBranding.removeLogo();
    expect(CompanyBranding.current.value.logo, isNull);
    expect(CompanyBranding.current.value.details.logoAssetRef, isEmpty);
  });

  test('логотип не попадает в JSON реквизитов — только ссылка', () {
    const details = CompanyDetails(
      name: 'ООО Тест',
      logoAssetRef: 'asset-1.png',
    );
    final json = details.toJson();
    expect(json['logoAssetRef'], 'asset-1.png');
    final restored = CompanyDetails.fromJson(json);
    expect(restored.hasLogo, isTrue);
    expect(restored.logoAssetRef, 'asset-1.png');
  });

  testWidgets('смета: логотип и строка реквизитов в шапке', (tester) async {
    final branding = CompanyBrandingState(
      details: const CompanyDetails(
        name: 'ООО Мягкие окна',
        inn: '7701234567',
        phone: '+7 999 123-45-67',
      ),
      logo: png,
      showOnSheets: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstimateSheet(
            project: const OrderProject(),
            prices: const PriceList.defaults(),
            company: branding,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ООО Мягкие окна'), findsOneWidget);
    expect(find.textContaining('ИНН 7701234567'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('смета: выключено — шапка как раньше', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstimateSheet(
            project: const OrderProject(),
            prices: const PriceList.defaults(),
            company: const CompanyBrandingState(
              details: CompanyDetails(name: 'ООО Скрытое'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ООО Скрытое'), findsNothing);
  });

  testWidgets('чертёж: логотип и название в штампе', (tester) async {
    final branding = CompanyBrandingState(
      details: const CompanyDetails(
        name: 'ООО Мягкие окна',
        phone: '+7 999 123-45-67',
      ),
      logo: png,
      showOnSheets: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingSheet(
            project: const OrderProject(),
            company: branding,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('ООО Мягкие окна'), findsWidgets);
    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('кнопка «Компания» в шапке открывает настройки', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: app.BuilderScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('company-appbar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('company-appbar')));
    await tester.pumpAndSettle();
    expect(find.text('Компания на листах'), findsWidgets);
    expect(find.byKey(const Key('company-name')), findsOneWidget);
    expect(find.byKey(const Key('company-logo-load')), findsOneWidget);
  });

  testWidgets('панель: тумблер включает показ компании', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: ParamsPanel(
              project: const OrderProject(),
              issues: const [],
              onChanged: (_) {},
              onReset: () {},
            ),
          ),
        ),
      ),
    );
    final toggle = find.byKey(const Key('company-on-sheets-toggle'));
    await tester.scrollUntilVisible(
      toggle,
      600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(CompanyBranding.current.value.showOnSheets, isTrue);
    expect(find.byKey(const Key('company-settings')), findsOneWidget);
  });
}
