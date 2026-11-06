import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/services/company_branding.dart';

void main() {
  test('логотип показывается только в выбранных документах', () {
    final state = CompanyBrandingState(
      logo: Uint8List.fromList([1, 2, 3]),
      showOnSheets: true,
      logoDocuments: const {LogoDocument.estimate},
    );
    expect(state.showLogoIn(LogoDocument.estimate), isTrue);
    expect(state.showLogoIn(LogoDocument.drawing), isFalse);
    expect(state.logoPlacement, LogoPlacement.left);
  });

  test('положение и документы сохраняются в состоянии', () {
    final state = const CompanyBrandingState().copyWith(
      logoPlacement: LogoPlacement.right,
      logoDocuments: const {LogoDocument.clientReport},
    );
    expect(state.logoPlacement, LogoPlacement.right);
    expect(state.showLogoIn(LogoDocument.clientReport), isFalse); // нет логотипа
    expect(state.logoDocuments, {LogoDocument.clientReport});
  });
}
