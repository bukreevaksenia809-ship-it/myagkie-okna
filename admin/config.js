// Внутренняя админка производства.
// Секрет здесь НЕ хранится: он зашифрован паролем (PBKDF2 + AES-GCM) и
// расшифровывается только после ввода пароля в браузере.
window.OKNA_CONFIG = {
  projectId: 'okna-7dbf8',
  apiKey: 'AIzaSyAwOQn1TDzcApHt1PKmhxoQfFAtraYSaA4',
  secretSalt: 'pYEaRKX94RDGY9cKupTcwA==',
  secretIv: 'EyC/kWTcWxlZZhD+',
  secretCipher: 'Ux+7OuRgzagHfm1NTD6Y/fOYKVtInuOyuD0XSlWpvXie8lH8WMaBIHoc4QcOm9B56w==',
  kdfIterations: 200000,
};
