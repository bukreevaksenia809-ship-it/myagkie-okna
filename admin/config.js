// Внутренняя админка производства.
// Секрет здесь НЕ хранится: он зашифрован паролем (PBKDF2 + AES-GCM) и
// расшифровывается только после ввода пароля в браузере.
window.OKNA_CONFIG = {
  projectId: 'okna-7dbf8',
  apiKey: 'AIzaSyAwOQn1TDzcApHt1PKmhxoQfFAtraYSaA4',
  secretSalt: 'DCa5CxgAFufv2Xc7N0Oi2Q==',
  secretIv: 'vZn6MdHyMgmXHoX+',
  secretCipher: 'WNYrggSQFd39GjhAT91Cm7EVvn9TOWtWbtRXsRAG638hYGm0ta+HzE8q6j4E0Ebjog==',
  kdfIterations: 200000,
  // Адрес Cloudflare Worker для загрузки DMG/EXE/ZIP (появится после deploy).
  uploadUrl: '',
};
