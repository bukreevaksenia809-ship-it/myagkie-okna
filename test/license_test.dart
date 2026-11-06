import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/services/license.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('в тестовом режиме лицензия активна и сеть не трогается', () async {
    final state = await LicenseService.check();
    expect(state.active, isTrue);
  });

  test('активация нормализует ключ', () async {
    final state = await LicenseService.activate(' ye9j emdp 37da b9dt ');
    expect(state.active, isTrue);
    expect(state.key, 'YE9J-EMDP-37DA-B9DT');
  });
}
