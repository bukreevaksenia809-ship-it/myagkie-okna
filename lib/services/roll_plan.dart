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
List<RollPlan> buildRollPlans(OrderProject project) {
  final result = <RollPlan>[];
  for (final material in project.materialsInOrder) {
    final pieces = <RollPiece>[];
    for (var i = 0; i < project.windowCount; i++) {
      final window = project.windows[i];
      if (window.material != material) continue;
      final spec = WindowSpec.of(window);
      pieces.add(
        RollPiece(
          id: '${i + 1}',
          label: project.labelFor(i),
          width: spec.filmCutWidthWithShrinkage,
          height: spec.filmCutHeightWithShrinkage,
        ),
      );
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
