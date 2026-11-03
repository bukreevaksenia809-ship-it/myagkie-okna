import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/window_presets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('пресет сохраняет окно, применяется и удаляется', () async {
    SharedPreferences.setMockInitialValues({});
    final store = WindowPresetStore();
    const params = WindowParams(
      windowType: WindowType.lifting,
      bottomWidth: 1800,
      leftHeight: 2200,
      fastenerType: FastenerType.metalFrenchLock,
      pocket: true,
      pocketWidth: 120,
    );

    final saved = await store.save('Беседка 1,8 × 2,2', params);
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Беседка 1,8 × 2,2');
    expect(saved.single.params.windowType, WindowType.lifting);
    expect(saved.single.params.fastenerType, FastenerType.metalFrenchLock);
    expect(saved.single.params.pocket, isTrue);

    // Новое чтение — данные переживают перезапуск.
    final again = await WindowPresetStore().load();
    expect(again.single.params.bottomWidth, 1800);
    expect(again.single.params.pocketWidth, 120);

    // Одинаковое имя заменяет пресет, а не дублирует.
    final replaced = await store.save('Беседка 1,8 × 2,2', params.copyWith(leftHeight: 2300));
    expect(replaced, hasLength(1));
    expect(replaced.single.params.leftHeight, 2300);

    final empty = await store.remove('Беседка 1,8 × 2,2');
    expect(empty, isEmpty);
  });
}
