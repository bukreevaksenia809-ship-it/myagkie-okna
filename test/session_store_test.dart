import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/session_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('сессия сохраняет и восстанавливает заказ', () async {
    final project = const OrderProject().copyWith(
      windows: const [
        WindowParams(bottomWidth: 1234, topWidth: 1234),
      ],
      status: OrderStatus.production,
    );
    await SessionStore.save(project);
    final restored = await SessionStore.load();
    expect(restored, isNotNull);
    expect(restored!.selected.bottomWidth, 1234);
    expect(restored.status, OrderStatus.production);
  });

  test('пустая сессия — null', () async {
    expect(await SessionStore.load(), isNull);
  });
}
