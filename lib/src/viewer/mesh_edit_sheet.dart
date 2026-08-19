import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MeshTransformRequest {
  const MeshTransformRequest({
    required this.tx,
    required this.ty,
    required this.tz,
    required this.rx,
    required this.ry,
    required this.rz,
    required this.sx,
    required this.sy,
    required this.sz,
  });

  final double tx;
  final double ty;
  final double tz;
  final double rx;
  final double ry;
  final double rz;
  final double sx;
  final double sy;
  final double sz;
}

Future<void> showMeshEditSheet({
  required BuildContext context,
  required MeshEditState initialState,
  required Future<MeshEditState> Function(MeshTransformRequest request) onApply,
  required Future<MeshEditState> Function() onUndo,
  required Future<MeshEditState> Function() onRedo,
  required Future<MeshEditState> Function() onReset,
  required Future<MeshEditState> Function() onDiscard,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _MeshEditSheet(
      initialState: initialState,
      onApply: onApply,
      onUndo: onUndo,
      onRedo: onRedo,
      onReset: onReset,
      onDiscard: onDiscard,
    ),
  );
}

class _MeshEditSheet extends StatefulWidget {
  const _MeshEditSheet({
    required this.initialState,
    required this.onApply,
    required this.onUndo,
    required this.onRedo,
    required this.onReset,
    required this.onDiscard,
  });

  final MeshEditState initialState;
  final Future<MeshEditState> Function(MeshTransformRequest request) onApply;
  final Future<MeshEditState> Function() onUndo;
  final Future<MeshEditState> Function() onRedo;
  final Future<MeshEditState> Function() onReset;
  final Future<MeshEditState> Function() onDiscard;

  @override
  State<_MeshEditSheet> createState() => _MeshEditSheetState();
}

class _MeshEditSheetState extends State<_MeshEditSheet> {
  late MeshEditState state = widget.initialState;
  bool running = false;
  String? error;

  final tx = TextEditingController(text: '0');
  final ty = TextEditingController(text: '0');
  final tz = TextEditingController(text: '0');
  final rx = TextEditingController(text: '0');
  final ry = TextEditingController(text: '0');
  final rz = TextEditingController(text: '0');
  final sx = TextEditingController(text: '1');
  final sy = TextEditingController(text: '1');
  final sz = TextEditingController(text: '1');

  @override
  void dispose() {
    for (final controller in [tx, ty, tz, rx, ry, rz, sx, sy, sz]) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  MeshTransformRequest? _request() {
    final values = [tx, ty, tz, rx, ry, rz, sx, sy, sz]
        .map(_number)
        .toList(growable: false);
    if (values.any((value) => value == null || !value.isFinite)) return null;
    if (values[6]! <= 0 || values[7]! <= 0 || values[8]! <= 0) return null;
    return MeshTransformRequest(
      tx: values[0]!,
      ty: values[1]!,
      tz: values[2]!,
      rx: values[3]!,
      ry: values[4]!,
      rz: values[5]!,
      sx: values[6]!,
      sy: values[7]!,
      sz: values[8]!,
    );
  }

  void _resetInputs() {
    for (final controller in [tx, ty, tz, rx, ry, rz]) {
      controller.text = '0';
    }
    for (final controller in [sx, sy, sz]) {
      controller.text = '1';
    }
  }

  Future<void> _run(Future<MeshEditState> Function() action) async {
    if (running) return;
    setState(() {
      running = true;
      error = null;
    });
    try {
      final next = await action();
      if (!mounted) return;
      setState(() => state = next);
    } on PlatformException catch (caught) {
      if (!mounted) return;
      setState(() => error = caught.message ?? caught.code);
    } catch (caught) {
      if (!mounted) return;
      setState(() => error = caught.toString());
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> _apply() async {
    final request = _request();
    if (request == null) {
      setState(() => error = '请输入有效数值；缩放 X/Y/Z 必须大于 0。');
      return;
    }
    await _run(() => widget.onApply(request));
    if (mounted && error == null) _resetInputs();
  }

  Future<void> _discard() async {
    if (running) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('退出网格编辑？'),
            content: const Text(
              '当前网格工作副本和撤销/重做历史会被丢弃，并重新打开原始源文档。已导出的文件不会受影响。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('恢复原模型'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await _run(widget.onDiscard);
    if (mounted && error == null && !state.active) Navigator.of(context).pop();
  }

  Widget _axisFields(
    String title,
    String suffix,
    TextEditingController x,
    TextEditingController y,
    TextEditingController z,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final pair in [('X', x), ('Y', y), ('Z', z)]) ...[
              Expanded(
                child: TextField(
                  controller: pair.$2,
                  enabled: !running,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[-+0-9.eE]')),
                  ],
                  decoration: InputDecoration(
                    labelText: pair.$1,
                    suffixText: suffix,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (pair.$1 != 'Z') const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final revision = state.cursor < 0 ? 0 : state.cursor;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.transform),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('网格工作副本编辑', style: theme.textTheme.titleLarge),
                    Text(
                      '${state.sourceFormatId.toUpperCase()} 源文件保持不变 · 当前版本 $revision',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (running)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Material(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '位移 / 旋转 / 缩放作用于当前显示网格，不会写回 STEP、IGES、3DM、FCStd 等源 CAD。每次“应用”生成一个可撤销版本；导出 OBJ/STL 时写出当前工作副本。',
              ),
            ),
          ),
          const SizedBox(height: 16),
          _axisFields('位移', '', tx, ty, tz),
          const SizedBox(height: 14),
          _axisFields('旋转', '°', rx, ry, rz),
          const SizedBox(height: 14),
          _axisFields('缩放', '×', sx, sy, sz),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: running ? null : () => unawaited(_apply()),
            icon: const Icon(Icons.check),
            label: const Text('应用变换'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: running || !state.canUndo
                      ? null
                      : () => unawaited(_run(widget.onUndo)),
                  icon: const Icon(Icons.undo),
                  label: const Text('撤销'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: running || !state.canRedo
                      ? null
                      : () => unawaited(_run(widget.onRedo)),
                  icon: const Icon(Icons.redo),
                  label: const Text('重做'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: running || revision <= 0
                      ? null
                      : () => unawaited(_run(widget.onReset)),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重置'),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          const Divider(),
          TextButton.icon(
            onPressed: running ? null : () => unawaited(_discard()),
            icon: const Icon(Icons.restore),
            label: const Text('退出编辑并恢复原模型'),
          ),
        ],
      ),
    );
  }
}
