import 'package:flutter_test/flutter_test.dart';

import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

void main() {
  test('Оксфорд: площадь канта считается по длине и ширине рулона', () {
    const params = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      rollBottom: 100,
      rollTop: 100,
      rollLeft: 100,
      rollRight: 100,
      edgeMaterial: EdgeMaterial.oxford600,
      edgeColor: EdgeColor.brown,
    );
    final spec = WindowSpec.of(params);
    // Периметр 2 × (2000 + 1500) = 7000 мм, рулон 100 мм.
    expect(spec.edgeAreaM2, closeTo(0.7, 0.001));
    expect(spec.edgeMaterialNote, contains('Оксфорд'));
    expect(spec.edgeMaterialNote, contains('коричневый'));
    expect(spec.edgeMaterialNote, contains('0,70 м²'));
    expect(spec.edgeSummary, contains('Оксфорд'));
    expect(spec.edgeSummary, contains('0,70 м²'));
  });

  test('Ткань скрин: кант стачивается, площадь не теряется', () {
    const params = WindowParams(
      bottomWidth: 1200,
      topWidth: 1200,
      leftHeight: 2000,
      rightHeight: 2000,
      rollBottom: 120,
      rollTop: 120,
      rollLeft: 120,
      rollRight: 120,
      edgeMaterial: EdgeMaterial.screenFabric,
      edgeColor: EdgeColor.grey,
    );
    final spec = WindowSpec.of(params);
    expect(spec.edgeAreaM2, greaterThan(0));
    expect(spec.edgeMaterialNote, contains('Ткань скрин'));
    expect(spec.edgeMaterialNote, contains('серый'));
    expect(spec.edgeMaterialNote, contains('м²'));
    expect(spec.params.edgeMaterial.isWelded, isFalse);
  });
}
