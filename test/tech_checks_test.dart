import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/tech_checks.dart';

/// Эталонное окно без технологических замечаний: 1500 × 2520 мм, окантовка
/// 100 мм (готовых 50 мм), шаг люверсов 300 мм, круглые люверсы, усадка 1,5 %.
const _correct = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  eyeletStep: 300,
);

/// Первая проверка с указанным правилом — или null, если её нет.
TechCheck? _check(List<TechCheck> checks, String ruleId) {
  for (final check in checks) {
    if (check.ruleId == ruleId) return check;
  }
  return null;
}

void main() {
  group('Люверсы', () {
    test('интервал 900 мм даёт предупреждение с рекомендацией', () {
      final checks = techChecksFor(_correct.copyWith(eyeletStep: 900));
      final check = _check(checks, 'eyelet-step-loose');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
      expect(check.explanation, isNotEmpty);
      expect(check.reason, check.explanation);
      expect(check.recommendation, isNotEmpty);
      expect(check.field, ParamField.eyeletStep);
    });

    test('интервал 600 мм — справка, а не запрет', () {
      final checks = techChecksFor(_correct.copyWith(eyeletStep: 600));
      final check = _check(checks, 'eyelet-step-wide');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.info);
      expect(_check(checks, 'eyelet-step-loose'), isNull);
    });

    test('интервал 100 мм — предупреждение о перерасходе', () {
      final checks = techChecksFor(_correct.copyWith(eyeletStep: 100));
      final check = _check(checks, 'eyelet-step-tight');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
    });

    test('шаг 300 мм и корректные параметры — без ошибок', () {
      final checks = techChecksFor(_correct);

      expect(checks.where((check) => check.severity == TechSeverity.error),
          isEmpty);
      expect(hasBlockingTechChecks(checks), isFalse);
    });

    test('люверс, поднятый от угла на 20 мм, — предупреждение', () {
      final checks = techChecksFor(_correct.copyWith(eyeletCornerOffset: 20));
      final check = _check(checks, 'eyelet-corner-danger');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
    });
  });

  group('Молнии', () {
    test('две молнии ближе 300 мм дают предупреждение', () {
      final params = _correct.copyWith(zippers: const [
        ZipperSpec(centered: false, offsetMm: 400),
        ZipperSpec(centered: false, offsetMm: 600),
      ]);
      final checks = techChecksFor(params);
      final check = _check(checks, 'zipper-spacing-near');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
      expect(check.title, contains('200'));
    });

    test('молния ближе 150 мм к кромке плёнки — предупреждение', () {
      final params = _correct.copyWith(zippers: const [
        ZipperSpec(centered: false, offsetMm: 100),
      ]);
      final check = _check(techChecksFor(params), 'zipper-edge-near');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
    });

    test('молния в окне с карманом — предупреждение', () {
      final params = _correct.copyWith(
        pocket: true,
        zippers: const [ZipperSpec(centered: true)],
      );
      final check = _check(techChecksFor(params), 'zipper-pocket-axis');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
    });

    test('молния скрина ближе 100 мм к кромке подворота — предупреждение', () {
      const screen = WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        hemBottomMm: 40,
        hemRightMm: 40,
        hemTopMm: 40,
        hemLeftMm: 40,
        zippers: [ZipperSpec(centered: false, offsetMm: 100)],
      );
      final checks = techChecksFor(screen);
      final check = _check(checks, 'screen-zipper-hem-near');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
      expect(check.title, contains('подворота'));
      expect(check.recommendation, contains('100'));
      // Правило ПВХ про 150 мм к плёнке к скрину не применяется.
      expect(_check(checks, 'zipper-edge-near'), isNull);
    });

    test('молния скрина по центру — запас до подворота достаточный', () {
      const screen = WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        zippers: [ZipperSpec(centered: true)],
      );
      final checks = techChecksFor(screen);

      expect(_check(checks, 'screen-zipper-hem-near'), isNull);
    });
  });

  group('Спайка окон', () {
    test('спайка стороны с крепежом на ней — предупреждение', () {
      final withFastener = _correct.copyWith(
        weldedSides: const [EdgeSide.left],
        removeEyeletsOnWelded: false,
      );
      final checks = techChecksFor(withFastener);
      final check = _check(checks, 'welded-side-fastener');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);

      // Без крепежа на спаянной стороне предупреждения быть не должно.
      final withoutFastener =
          _correct.copyWith(weldedSides: const [EdgeSide.left]);
      expect(
        _check(techChecksFor(withoutFastener), 'welded-side-fastener'),
        isNull,
      );
    });

    test('спайка обеих боковых сторон — предупреждение о зажатом окне', () {
      final params = _correct.copyWith(
        weldedSides: const [EdgeSide.left, EdgeSide.right],
      );
      final check = _check(techChecksFor(params), 'welded-both-sides');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
    });
  });

  group('Вырезы', () {
    test('круглый вырез 80 мм — справка или предупреждение', () {
      final params = _correct.copyWith(cutouts: const [
        Cutout(
          shape: CutoutShape.circle,
          width: 80,
          height: 80,
          centerXMm: 700,
          centerYMm: 800,
        ),
      ]);
      final check = _check(techChecksFor(params), 'cutout-circle-small');

      expect(check, isNotNull);
      expect(
        [TechSeverity.info, TechSeverity.warning],
        contains(check!.severity),
      );
    });

    test('вырез в 60 мм от окантовки — предупреждение о тонкой перемычке',
        () {
      final params = _correct.copyWith(cutouts: const [
        Cutout(
          width: 300,
          height: 300,
          centerXMm: 700,
          centerYMm: 210,
        ),
      ]);
      final check = _check(techChecksFor(params), 'cutout-bridge-thin');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
    });
  });

  group('Заказ', () {
    test('два одинаковых окна — справка о совпадении', () {
      const project = OrderProject(windows: [_correct, _correct]);
      final check = _check(techChecksForOrder(project), 'order-duplicate-window');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.info);
      expect(check.title, contains('№1'));
      expect(check.title, contains('№2'));
    });

    test('проверки заказа не дублируют проверки окон', () {
      final project = OrderProject(windows: [
        _correct,
        _correct.copyWith(eyeletStep: 900),
      ]);
      final orderChecks = techChecksForOrder(project);

      // Проверка конкретного окна живёт в techChecksFor.
      expect(_check(orderChecks, 'eyelet-step-loose'), isNull);
      expect(orderChecks.every((check) => check.windowIndex == null), isTrue);

      // Для сводного экрана проверку можно пометить номером окна.
      final windowCheck = _check(
        techChecksFor(project.windows[1]),
        'eyelet-step-loose',
      )!
          .forWindow(1);
      expect(windowCheck.windowIndex, 1);
      expect(windowCheck.title, contains('Окно №2'));
    });

    test('много разных материалов и большая площадь — проверки заказа', () {
      const project = OrderProject(windows: [
        _correct,
        WindowParams(
          material: FilmMaterial.tintedPvc,
          bottomWidth: 1500,
          topWidth: 1500,
          leftHeight: 2520,
          rightHeight: 2520,
        ),
        WindowParams(
          material: FilmMaterial.mosquitoNet,
          bottomWidth: 1500,
          topWidth: 1500,
          leftHeight: 2520,
          rightHeight: 2520,
        ),
      ]);
      final checks = techChecksForOrder(project);

      expect(_check(checks, 'order-many-materials')?.severity,
          TechSeverity.warning);

      // 11 окон по 3,78 м² — больше 40 м².
      final large = OrderProject(
        windows: List<WindowParams>.generate(11, (_) => _correct),
      );
      final largeChecks = techChecksForOrder(large);
      expect(_check(largeChecks, 'order-area-large')?.severity,
          TechSeverity.info);
    });
  });

  group('Остальные правила', () {
    test('подъёмное окно: нагрузка на ремни, высота и крепёж', () {
      final params = _correct.copyWith(
        windowType: WindowType.lifting,
        bottomWidth: 2800,
        topWidth: 2800,
        leftHeight: 3200,
        rightHeight: 3200,
        fastenerType: FastenerType.eyeletsOnly,
      );
      final checks = techChecksFor(params);

      expect(_check(checks, 'lifting-strap-load')?.severity,
          TechSeverity.warning);
      expect(_check(checks, 'lifting-height')?.severity, TechSeverity.warning);
      expect(_check(checks, 'lifting-eyelets-only')?.severity,
          TechSeverity.warning);
      expect(params.liftStrapCount, 3);
    });

    test('карман: угловые люверсы подняты автоматически', () {
      final params = _correct.copyWith(pocket: true, pocketWidth: 100);
      final checks = techChecksFor(params);

      expect(_check(checks, 'pocket-corner-lifted'), isNull);
    });

    test('глухое окно с овальным люверсом — без запрета', () {
      // Тип люверса доступен на любом окне: правила «глухое + овальный» нет.
      final params = _correct.copyWith(eyeletType: EyeletType.oval42x22);
      final checks = techChecksFor(params);

      expect(_check(checks, 'fixed-window-oval-eyelet'), isNull);
      expect(params.effectiveEyeletType, EyeletType.oval42x22);
    });

    test('скрин с крепежом: правило «крепёж игнорируется» не срабатывает', () {
      // Глухой скрин со скобами — противоречий нет: крепёж ставится по
      // подвороту.
      final screen = _correct.copyWith(
        material: FilmMaterial.screen,
        fastenerType: FastenerType.turnBuckles,
      );
      final checks = techChecksFor(screen);

      expect(screen.isScreen, isTrue);
      expect(screen.isLifting, isFalse);
      expect(_check(checks, 'screen-fastener-ignored'), isNull);
      expect(_check(checks, 'lifting-eyelets-only'), isNull);
    });

    test('подъёмный скрин с «только люверсы»: предупреждение остаётся', () {
      final screen = _correct.copyWith(
        material: FilmMaterial.screen,
        windowType: WindowType.lifting,
        fastenerType: FastenerType.eyeletsOnly,
      );
      final checks = techChecksFor(screen);

      expect(_check(checks, 'lifting-eyelets-only')?.severity,
          TechSeverity.warning);
      // А со скобами предупреждения нет: поднимать есть чем.
      final withBuckles = _correct.copyWith(
        material: FilmMaterial.screen,
        windowType: WindowType.lifting,
        fastenerType: FastenerType.turnBuckles,
      );
      expect(
        _check(techChecksFor(withBuckles), 'lifting-eyelets-only'),
        isNull,
      );
    });

    test('верх без люверсов и не спаян — предупреждение «нечем крепить»', () {
      final params = _correct.copyWith(noEyeletsTop: true);
      final check = _check(techChecksFor(params), 'eyelet-top-unfastened');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
      expect(check.title, 'Верх нечем крепить');
      expect(check.explanation, contains('не спаяна'));

      // Если сторона спаяна с соседним окном — крепёж там не нужен.
      final welded = params.copyWith(weldedSides: const [EdgeSide.top]);
      expect(_check(techChecksFor(welded), 'eyelet-top-unfastened'), isNull);
    });

    test('низ без люверсов и не спаян — предупреждение', () {
      final params = _correct.copyWith(noEyeletsBottom: true);
      final check = _check(techChecksFor(params), 'eyelet-bottom-unfastened');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
      expect(check.title, 'Низ нечем крепить');

      final welded = params.copyWith(weldedSides: const [EdgeSide.bottom]);
      expect(_check(techChecksFor(welded), 'eyelet-bottom-unfastened'), isNull);
    });

    test('без выключенных сторон предупреждений о крепеже нет', () {
      final checks = techChecksFor(_correct);
      expect(_check(checks, 'eyelet-top-unfastened'), isNull);
      expect(_check(checks, 'eyelet-bottom-unfastened'), isNull);
    });

    test('усадка 4 % — предупреждение', () {
      final params = _correct.copyWith(shrinkagePercent: 4);
      final check = _check(techChecksFor(params), 'shrinkage-high');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
    });

    test('высокая трапеция с разницей 600 мм — предупреждение', () {
      final params = _correct.copyWith(
        bottomWidth: 3000,
        topWidth: 2400,
        leftHeight: 2600,
        rightHeight: 2600,
      );
      final check = _check(techChecksFor(params), 'section-large-diff');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.warning);
    });

    test('слишком узкая плёнка — ошибка', () {
      final params = _correct.copyWith(
        bottomWidth: 300,
        topWidth: 300,
        leftHeight: 400,
        rightHeight: 400,
      );
      final check = _check(techChecksFor(params), 'film-narrow');

      expect(check, isNotNull);
      expect(check!.severity, TechSeverity.error);
    });
  });

  group('Блокирующие проверки', () {
    test('hasBlockingTechChecks истинно только при наличии error', () {
      expect(hasBlockingTechChecks(const []), isFalse);
      expect(hasBlockingTechChecks(techChecksFor(_correct)), isFalse);

      final tiny = _correct.copyWith(
        bottomWidth: 300,
        topWidth: 300,
        leftHeight: 400,
        rightHeight: 400,
      );
      final checks = techChecksFor(tiny);
      expect(checks.any((check) => check.severity == TechSeverity.error),
          isTrue);
      expect(hasBlockingTechChecks(checks), isTrue);

      const info = TechCheck(
        ruleId: 'manual-info',
        severity: TechSeverity.info,
        title: 'Справка',
        explanation: 'Причина',
        recommendation: 'Рекомендация',
      );
      const warning = TechCheck(
        ruleId: 'manual-warning',
        severity: TechSeverity.warning,
        title: 'Замечание',
        explanation: 'Причина',
        recommendation: 'Рекомендация',
      );
      expect(hasBlockingTechChecks(const [info, warning]), isFalse);
    });

    test('проверки отсортированы: ошибки, замечания, справки', () {
      final checks = techChecksFor(_correct.copyWith(
        bottomWidth: 300,
        topWidth: 300,
        leftHeight: 400,
        rightHeight: 400,
        eyeletStep: 600,
      ));
      final ranks = [for (final check in checks) check.severity.rank];

      expect(ranks, orderedEquals(List<int>.of(ranks)..sort()));
      expect(checks.first.severity, TechSeverity.error);
    });
  });
}
