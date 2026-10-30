import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';

class _Host extends StatefulWidget {
  const _Host({super.key, required this.initial});
  final OrderProject initial;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late OrderProject project = widget.initial;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 420,
        height: 800,
        child: ParamsPanel(
          project: project,
          issues: const [],
          onChanged: (value) => setState(() => project = value),
          onReset: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('узкий рулон: предупреждение и кнопка спайки', (tester) async {
    const params = WindowParams(
      bottomWidth: 2200,
      topWidth: 2200,
      leftHeight: 2200,
      rightHeight: 2200,
      rollBottom: 100,
      rollTop: 100,
      rollLeft: 100,
      rollRight: 100,
      pvcHeightAllowanceEnabled: false,
    );
    const project = OrderProject(
      windows: [params],
      rollWidths: {FilmMaterial.clearPvc: 2000},
    );
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key, initial: project));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scrollable = find
        .descendant(
          of: find.byType(ParamsPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Ширина рулона'),
      600,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('roll-width-warning')), findsOneWidget);
    expect(find.textContaining('шире рулона'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('splice-add')));
    await tester.tap(find.byKey(const Key('splice-add')));
    await tester.pumpAndSettle();
    expect(key.currentState!.project.selected.spliceStripMm, greaterThan(0));
    expect(find.byKey(const Key('roll-width-splice')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('спайка сохраняется в JSON', () {
    const params = WindowParams(
      spliceStripMm: 300,
      spliceSide: FilmSpliceSide.left,
    );
    final restored = windowFromJson(windowToJson(params));
    expect(restored.spliceStripMm, 300);
    expect(restored.spliceSide, FilmSpliceSide.left);
    expect(restored.hasSplice, isTrue);
  });
}
