/// Адрес backend и общий ключ задаются только при сборке.
///
/// В магазинной сборке (`STORE_BUILD=true`) они пустые — в APK не попадают
/// ни адрес Firestore, ни админский ключ. Для полной сборки передайте:
/// `--dart-define=OKNA_BACKEND=... --dart-define=OKNA_SECRET=...`
const String kBackendProject =
    String.fromEnvironment('OKNA_PROJECT', defaultValue: 'okna-7dbf8');
const String kBackendApiKey = String.fromEnvironment(
  'OKNA_API_KEY',
  defaultValue: 'AIzaSyAwOQn1TDzcApHt1PKmhxoQfFAtraYSaA4',
);
const String kBackendBase = String.fromEnvironment('OKNA_BACKEND');
const String kBackendSecret = String.fromEnvironment('OKNA_SECRET');
