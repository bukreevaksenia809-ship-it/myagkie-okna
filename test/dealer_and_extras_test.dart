import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';

void main() {
  const window = WindowParams(
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 2000,
    rightHeight: 2000,
  );

  test('дополнительные позиции попадают в смету по количеству', () {
    const project = OrderProject(
      windows: [window],
      extraQuantities: {
        PriceList.extraDelivery: 2,
        PriceList.extraShadowSail: 12.5,
        PriceList.extraBeam: 8,
        PriceList.extraZip: 3,
      },
    );
    const prices = PriceList(
      deliveryPerPiece: 1000,
      shadowSailPerM2: 2000,
      romanAwningPerM2: 2500,
      beamPerM: 500,
      decorBeamPerM: 700,
      zipPerM2: 1500,
    );
    final estimate = Estimate.of(project, prices);
    final extras = estimate.lines
        .where((line) => line.group == EstimateGroup.extra)
        .toList();
    expect(extras, hasLength(4));
    expect(
      extras.firstWhere((line) => line.title.contains('Доставка')).amount,
      closeTo(2000, 1e-9),
    );
    expect(
      extras.firstWhere((line) => line.title.contains('Теневой')).quantity,
      12.5,
    );
    expect(
      extras.firstWhere((line) => line.title.contains('Брус')).unit,
      'пог.м',
    );
    expect(
      extras.firstWhere((line) => line.title.contains('Zip')).unit,
      'м²',
    );
  });

  test('дилерская смета считается по своим ценам', () {
    const project = OrderProject(
      windows: [window],
      extraQuantities: {PriceList.extraDelivery: 1},
    );
    const client = PriceList(deliveryPerPiece: 1000);
    const dealer = PriceList(deliveryPerPiece: 800);
    final clientTotal = Estimate.of(project, client).total;
    final dealerTotal = Estimate.of(project, dealer).total;
    expect(dealerTotal, lessThan(clientTotal));
  });

  test('новые цены и количества переживают JSON', () {
    const prices = PriceList(
      deliveryPerPiece: 100,
      shadowSailPerM2: 200,
      romanAwningPerM2: 300,
      beamPerM: 400,
      decorBeamPerM: 500,
      zipPerM2: 600,
    );
    final restored = PriceList.fromJson(prices.toJson());
    expect(restored.deliveryPerPiece, 100);
    expect(restored.shadowSailPerM2, 200);
    expect(restored.romanAwningPerM2, 300);
    expect(restored.beamPerM, 400);
    expect(restored.decorBeamPerM, 500);
    expect(restored.zipPerM2, 600);

    const project = OrderProject(
      windows: [window],
      extraQuantities: {PriceList.extraBeam: 7.5},
    );
    final order = orderFromJson(orderToJson(project));
    expect(order.extraQuantities[PriceList.extraBeam], 7.5);
  });
}
