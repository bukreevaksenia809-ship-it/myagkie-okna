import '../models/window_params.dart';

/// Внутренние размеры полотна по четырём сторонам, мм.
typedef InnerSides = ({
  double topWidth,
  double bottomWidth,
  double leftHeight,
  double rightHeight,
});

/// Наружные размеры окна по четырём сторонам, мм.
typedef OuterSides = ({
  double topWidth,
  double bottomWidth,
  double leftHeight,
  double rightHeight,
});

/// Внутренний размер → наружный габарит.
///
/// Внутренний размер — видимая плёнка/ткань между внутренними кромками
/// окантовки. К ширине сверху и снизу добавляются готовые полосы слева/справа,
/// к высоте слева и справа — полосы сверху/снизу. У скрина подворот загибается
/// внутрь, поэтому его наружный размер равен внутреннему.
OuterSides outerSidesFromInner(WindowParams params, InnerSides inner) {
  if (params.isScreen) {
    return (
      topWidth: inner.topWidth,
      bottomWidth: inner.bottomWidth,
      leftHeight: inner.leftHeight,
      rightHeight: inner.rightHeight,
    );
  }
  final left = WindowParams.finishedEdgeWidth(params.rollLeft);
  final right = WindowParams.finishedEdgeWidth(params.rollRight);
  final top = WindowParams.finishedEdgeWidth(params.rollTop);
  final bottom = WindowParams.finishedEdgeWidth(params.rollBottom);
  return (
    topWidth: inner.topWidth + left + right,
    bottomWidth: inner.bottomWidth + left + right,
    leftHeight: inner.leftHeight + top + bottom,
    rightHeight: inner.rightHeight + top + bottom,
  );
}

/// Наружный габарит → внутренние размеры по четырём сторонам.
InnerSides innerSidesFromOuter(WindowParams params) {
  if (params.isScreen) {
    return (
      topWidth: params.topWidth,
      bottomWidth: params.bottomWidth,
      leftHeight: params.leftHeight,
      rightHeight: params.rightHeight,
    );
  }
  final left = WindowParams.finishedEdgeWidth(params.rollLeft);
  final right = WindowParams.finishedEdgeWidth(params.rollRight);
  final top = WindowParams.finishedEdgeWidth(params.rollTop);
  final bottom = WindowParams.finishedEdgeWidth(params.rollBottom);
  double positive(double value) => value < 1 ? 1 : value;
  return (
    topWidth: positive(params.topWidth - left - right),
    bottomWidth: positive(params.bottomWidth - left - right),
    leftHeight: positive(params.leftHeight - top - bottom),
    rightHeight: positive(params.rightHeight - top - bottom),
  );
}

/// Совместимый вариант для простого прямоугольника: ширина × высота.
({double width, double height}) outerSizeFromInner(
  WindowParams params,
  double innerWidth,
  double innerHeight,
) {
  final outer = outerSidesFromInner(
    params,
    (
      topWidth: innerWidth,
      bottomWidth: innerWidth,
      leftHeight: innerHeight,
      rightHeight: innerHeight,
    ),
  );
  return (width: outer.bottomWidth, height: outer.leftHeight);
}

/// Совместимый вариант: внутренние ширина и высота по нижней/левой стороне.
({double width, double height}) innerSizeFromOuter(WindowParams params) {
  final inner = innerSidesFromOuter(params);
  return (width: inner.bottomWidth, height: inner.leftHeight);
}
