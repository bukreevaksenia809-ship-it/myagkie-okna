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
  final topSlant = params.topEdgeSlantMm;
  final bottomSlant = params.bottomEdgeSlantMm;
  final innerTopRun = math.sqrt(
    math.max(inner.topWidth * inner.topWidth - topSlant * topSlant, 0),
  );
  final innerBottomRun = math.sqrt(
    math.max(
      inner.bottomWidth * inner.bottomWidth - bottomSlant * bottomSlant,
      0,
    ),
  );
  return (
    topWidth: innerTopRun + left + right,
    bottomWidth: innerBottomRun + left + right,
    leftHeight: inner.leftHeight + top + bottom,
    rightHeight: inner.rightHeight + top + bottom,
  );
}

/// Наружный габарит → внутренние размеры по четырём сторонам.
///
/// Верхний и нижний внутренние размеры возвращаются как длина кромки
/// (гипотенуза): наклонная кромка длиннее горизонтальной проекции.
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
  final topSlant = params.topEdgeSlantMm;
  final bottomSlant = params.bottomEdgeSlantMm;
  final innerTopRun = positive(params.topWidth - left - right);
  final innerBottomRun = positive(params.bottomWidth - left - right);
  final innerTop = math.sqrt(
    math.max(innerTopRun * innerTopRun + topSlant * topSlant, 0),
  );
  final innerBottom = math.sqrt(
    math.max(innerBottomRun * innerBottomRun + bottomSlant * bottomSlant, 0),
  );
  return (
    topWidth: innerTop,
    bottomWidth: innerBottom,
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
