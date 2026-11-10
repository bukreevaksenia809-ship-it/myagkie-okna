import 'dart:math' as math;

import '../models/window_params.dart';

/// Внутренние размеры полотна по четырём сторонам, мм.
///
/// `topWidth` — это **длина наклонной верхней кромки** (гипотенуза), а не её
/// горизонтальная проекция: мастер измеряет видимую плёнку именно по кромке.
typedef InnerSides = ({
  double topWidth,
  double bottomWidth,
  double leftHeight,
  double rightHeight,
});

/// Наружные размеры окна по четырём сторонам, мм.
///
/// `topWidth` — горизонтальная проекция верхней кромки (то, что хранит
/// [WindowParams.topWidth]); наклонная длина считается из неё и перепада высот.
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
/// внутрь, поэтому полосы нулевые, а наружный размер равен внутреннему.
///
/// Верхний размер вводится по наклонной кромке: программа вычитает из
/// гипотенузы перепад высот, получает горизонтальную проекцию и добавляет
/// полосы окантовки слева/справа.
OuterSides outerSidesFromInner(WindowParams params, InnerSides inner) {
  final left = params.isScreen
      ? 0.0
      : WindowParams.finishedEdgeWidth(params.rollLeft);
  final right = params.isScreen
      ? 0.0
      : WindowParams.finishedEdgeWidth(params.rollRight);
  final top = params.isScreen
      ? 0.0
      : WindowParams.finishedEdgeWidth(params.rollTop);
  final bottom = params.isScreen
      ? 0.0
      : WindowParams.finishedEdgeWidth(params.rollBottom);
  final slant = params.topEdgeSlantMm;
  final innerRun = math.sqrt(
    math.max(inner.topWidth * inner.topWidth - slant * slant, 0),
  );
  return (
    topWidth: innerRun + left + right,
    bottomWidth: inner.bottomWidth + left + right,
    leftHeight: inner.leftHeight + top + bottom,
    rightHeight: inner.rightHeight + top + bottom,
  );
}

/// Наружный габарит → внутренние размеры по четырём сторонам.
///
/// Верхний внутренний размер возвращается как длина наклонной кромки.
InnerSides innerSidesFromOuter(WindowParams params) {
  final left = params.isScreen
      ? 0.0
      : WindowParams.finishedEdgeWidth(params.rollLeft);
  final right = params.isScreen
      ? 0.0
      : WindowParams.finishedEdgeWidth(params.rollRight);
  final top = params.isScreen
      ? 0.0
      : WindowParams.finishedEdgeWidth(params.rollTop);
  final bottom = params.isScreen
      ? 0.0
      : WindowParams.finishedEdgeWidth(params.rollBottom);
  double positive(double value) => value < 1 ? 1 : value;
  final slant = params.topEdgeSlantMm;
  final innerRun = positive(params.topWidth - left - right);
  final innerTop = math.sqrt(
    math.max(innerRun * innerRun + slant * slant, 0),
  );
  return (
    topWidth: innerTop,
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
