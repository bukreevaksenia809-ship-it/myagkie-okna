// «Другие позиции» (себестоимость): удаление статьи скрывает её из списка и
// расчёта, восстановление возвращает цену.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/services/cost_catalog.dart';
import 'package:soft_window_drawer/services/estimate.dart';

void main() {
  test('скрытая статья не участвует в себестоимости', () {
    final catalog = CostCatalog(
      costs: {PriceItemKeys.labor: 100},
      hidden: {PriceItemKeys.labor},
      configured: true,
    );
    expect(catalog.isHidden(PriceItemKeys.labor), isTrue);
    expect(catalog.costFor(PriceItemKeys.labor), isNull);
    final back = catalog.withHidden(PriceItemKeys.labor, hidden: false);
    expect(back.costFor(PriceItemKeys.labor), 100);
  });

  test('скрытые статьи переживают перезапуск', () async {
    SharedPreferences.setMockInitialValues({});
    final catalog = CostCatalog(
      costs: {PriceItemKeys.labor: 120},
      hidden: {PriceItemKeys.cutting},
      configured: true,
    );
    await catalog.save();
    final loaded = await CostCatalog().load();
    expect(loaded.isHidden(PriceItemKeys.cutting), isTrue);
    expect(loaded.costFor(PriceItemKeys.cutting), isNull);
    expect(loaded.costFor(PriceItemKeys.labor), 120);
  });
}
