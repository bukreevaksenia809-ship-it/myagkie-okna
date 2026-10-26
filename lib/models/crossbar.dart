import 'dart:math' as math;

/// Ориентация перемычки.
enum CrossbarAxis {
  horizontal('Горизонтальная'),
  vertical('Вертикальная');

  const CrossbarAxis(this.label);

  final String label;
}

/// Перемычка внутри полотна: полоса, напаянная на плёнку.
///
/// [positionMm] — центр полосы от нижней (горизонтальная) или левой
/// (вертикальная) внутренней кромки окантовки.
/// [widthMm] — ширина полосы, [weldMm] — напайка на каждое полотно.
/// Если [fullSpan] — полоса идёт от кромки до кромки и делит раскрой;
/// иначе это усилитель заданной [lengthMm].
class CrossbarSpec {
  const CrossbarSpec({
    this.axis = CrossbarAxis.horizontal,
    this.positionMm = 0,
    this.widthMm = 100,
    this.weldMm = 30,
    this.fullSpan = true,
    this.lengthMm = 0,
    this.alongMm = 0,
  });

  final CrossbarAxis axis;
  final double positionMm;
  final double widthMm;
  final double weldMm;
  final bool fullSpan;
  final double lengthMm;

  /// Смещение начала полосы вдоль окна для неполной перемычки, мм.
  final double alongMm;

  /// Свободная полоса между напайками: ширина минус две напайки.
  double get gapMm => math.max(0, widthMm - weldMm * 2);

  double lengthFor({required double innerWidth, required double innerHeight}) {
    final available = axis == CrossbarAxis.horizontal ? innerWidth : innerHeight;
    if (fullSpan) return available;
    return lengthMm.clamp(0.0, available);
  }

  CrossbarSpec copyWith({
    CrossbarAxis? axis,
    double? positionMm,
    double? widthMm,
    double? weldMm,
    bool? fullSpan,
    double? lengthMm,
    double? alongMm,
  }) => CrossbarSpec(
    axis: axis ?? this.axis,
    positionMm: positionMm ?? this.positionMm,
    widthMm: widthMm ?? this.widthMm,
    weldMm: weldMm ?? this.weldMm,
    fullSpan: fullSpan ?? this.fullSpan,
    lengthMm: lengthMm ?? this.lengthMm,
    alongMm: alongMm ?? this.alongMm,
  );

  Map<String, dynamic> toJson() => {
    'axis': axis.name,
    'positionMm': positionMm,
    'widthMm': widthMm,
    'weldMm': weldMm,
    'fullSpan': fullSpan,
    'lengthMm': lengthMm,
    'alongMm': alongMm,
  };

  factory CrossbarSpec.fromJson(Map<String, dynamic> json) => CrossbarSpec(
    axis: CrossbarAxis.values.firstWhere(
      (value) => value.name == json['axis'],
      orElse: () => CrossbarAxis.horizontal,
    ),
    positionMm: _double(json['positionMm'], 0),
    widthMm: _double(json['widthMm'], 100),
    weldMm: _double(json['weldMm'], 30),
    fullSpan: json['fullSpan'] != false,
    lengthMm: _double(json['lengthMm'], 0),
    alongMm: _double(json['alongMm'], 0),
  );

  static double _double(Object? value, double fallback) {
    if (value is num && value.isFinite) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }
}
