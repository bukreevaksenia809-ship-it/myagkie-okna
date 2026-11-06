import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';
import 'roll_packing.dart';

/// Раскладка одного материала на своём рулоне.
class RollPlan {
  const RollPlan({
    required this.material,
    required this.rollWidth,
    required this.layout,
  });

  final FilmMaterial material;
  final double rollWidth;
  final RollLayout layout;

  double get piecesArea => layout.placements.fold<double>(
        0,
        (sum, placement) => sum + placement.width * placement.height,
      );

  double get rollArea => rollWidth * layout.requiredLength;

  double get wastePercent => rollArea > 0
      ? ((rollArea - piecesArea) / rollArea * 100).clamp(0.0, 100.0)
      : 0.0;
}

/// Раскладка заготовок заказа по материалам (свой рулон на материал).
///
/// На рулон заготовки пакуются по ГАБАРИТНОМУ прямоугольнику — это упаковка,
/// и для трапеции прямоугольник описывает её сверху. В ведомости, смете и на
/// листе «Раскрой» при этом идёт ФАКТИЧЕСКАЯ площадь по контуру
/// ([WindowSpec.filmCutAreaM2] / [WindowSpec.filmCutAreaWithShrinkageM2]),
/// поэтому отход на рулоне и площадь в документах — разные числа, и это
/// осознанно: рулон режется прямоугольными картами, а материал считается по
/// реальной форме изделия.
List<RollPlan> buildRollPlans(OrderProject project) {
  final result = <RollPlan>[];
  for (final material in project.materialsInOrder) {
    final pieces = <RollPiece>[];
    for (var i = 0; i < project.windowCount; i++) {
      final window = project.windows[i];
      if (window.material != material) continue;
      final spec = WindowSpec.of(window);
      final width = spec.filmCutWidthWithShrinkage;
      final height = spec.filmCutHeightWithShrinkage;
      if (window.hasSplice &&
          window.spliceStripMm > 0.5 &&
          window.spliceStripMm < width - 0.5) {
        // Полотно шире рулона: на рулон кладём основной кусок и доборную
        // полосу отдельными заготовками — иначе раскладка «вылезет» за рулон.
        final main = width - window.spliceStripMm;
        pieces.add(
          RollPiece(
            id: '${i + 1}a',
            label: '${project.labelFor(i)} · основа',
            width: main,
            height: height,
          ),
        );
        pieces.add(
          RollPiece(
            id: '${i + 1}b',
            label: '${project.labelFor(i)} · полоса '
                '${formatMm(window.spliceStripMm)}',
            width: window.spliceStripMm,
            height: height,
          ),
        );
      } else {
        pieces.add(
          RollPiece(
            id: '${i + 1}',
            label: project.labelFor(i),
            // На рулон укладывается заготовка с припуском на раскрой и усадкой.
            width: width,
            height: height,
          ),
        );
      }
    }
    if (pieces.isEmpty) continue;
    final rollWidth = project.rollWidthFor(material);
    result.add(
      RollPlan(
        material: material,
        rollWidth: rollWidth,
        layout: packOnRoll(
          rollWidth: rollWidth,
          pieces: pieces,
          gap: project.rollGap,
        ),
      ),
    );
  }
  return result;
}
