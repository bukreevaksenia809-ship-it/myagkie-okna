import 'package:flutter/material.dart';

import '../services/license.dart';

/// Диалог активации: блокирует работу без ключа.
///
/// [blocking] — нельзя закрыть, пока ключ не активирован.
Future<LicenseState?> showLicenseDialog(
  BuildContext context, {
  required bool blocking,
  LicenseState? initial,
}) {
  return showDialog<LicenseState>(
    context: context,
    barrierDismissible: !blocking,
    builder: (context) => LicenseDialog(blocking: blocking, initial: initial),
  );
}

class LicenseDialog extends StatefulWidget {
  const LicenseDialog({
    super.key,
    required this.blocking,
    this.initial,
  });

  final bool blocking;
  final LicenseState? initial;

  @override
  State<LicenseDialog> createState() => _LicenseDialogState();
}

class _LicenseDialogState extends State<LicenseDialog> {
  final _controller = TextEditingController();
  LicenseState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
    _controller.text = LicenseService.savedKey ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    final result = await LicenseService.activate(_controller.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _state = result;
    });
    if (result.active) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _state;
    final error = state != null && !state.active ? state.message : null;
    return PopScope(
      canPop: !widget.blocking,
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.key_outlined,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.blocking
                            ? 'Активация программы'
                            : 'Лицензия',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.blocking
                      ? 'Введите ключ активации, который выдал поставщик. '
                            'Без ключа программа не запускается.'
                      : 'Ключ активации этого компьютера.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('license-key'),
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Ключ активации',
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _activate(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error,
                    key: const Key('license-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if (state != null && state.active) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          state.message,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (!widget.blocking)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Закрыть'),
                      ),
                    const Spacer(),
                    FilledButton.icon(
                      key: const Key('license-submit'),
                      onPressed: _busy ? null : _activate,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login, size: 18),
                      label: const Text('Активировать'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
