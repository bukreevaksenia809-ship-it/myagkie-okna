import 'dart:io';

/// Тестовое окружение Flutter выставляет FLUTTER_TEST=true — в нём сетевые
/// вызовы телеметрии не нужны.
bool get isTestEnvironment => Platform.environment['FLUTTER_TEST'] == 'true';
