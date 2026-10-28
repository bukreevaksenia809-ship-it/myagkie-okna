import '../models/window_params.dart';

/// Пересчёт внутреннего размера полотна в наружный габарит окна.
///
/// Внутренний размер — это видимая плёнка/ткань между внутренними кромками
/// окантовки. Наружный = внутренний + готовые полосы окантовки слева/справа
/// и сверху/снизу. Для скрина подвороты загибаются внутрь, поэтому наружный
/// размер совпадает с введённым внутренним (подворот не расширяет изделие).
({double width, double height}) outerSizeFromInner(
  WindowParams params,
  double innerWidth,
  double innerHeight,
) {
  if (params.isScreen) {
    return (width: innerWidth, height: innerHeight);
  }
  final left = WindowParams.finishedEdgeWidth(params.rollLeft);
  final right = WindowParams.finishedEdgeWidth(params.rollRight);
  final top = WindowParams.finishedEdgeWidth(params.rollTop);
  final bottom = WindowParams.finishedEdgeWidth(params.rollBottom);
  return (
    width: innerWidth + left + right,
    height: innerHeight + top + bottom,
  );
}

/// Внутренний размер по текущему наружному — для подписи в диалоге.
({double width, double height}) innerSizeFromOuter(WindowParams params) {
  if (params.isScreen) {
    return (width: params.bottomWidth, height: params.leftHeight);
  }
  final left = WindowParams.finishedEdgeWidth(params.rollLeft);
  final right = WindowParams.finishedEdgeWidth(params.rollRight);
  final top = WindowParams.finishedEdgeWidth(params.rollTop);
  final bottom = WindowParams.finishedEdgeWidth(params.rollBottom);
  return (
    width: (params.bottomWidth - left - right).clamp(1.0, double.infinity),
    height: (params.leftHeight - top - bottom).clamp(1.0, double.infinity),
  );
}
