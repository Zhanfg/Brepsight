import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ObjectVisibilityUpdater = Future<List<CadObjectPresentation>> Function(
  String objectId,
  bool visible,
);

Future<List<CadObjectPresentation>?> showObjectPresentationSheet({
  required BuildContext context,
  required List<CadObjectPresentation> objects,
  required ObjectVisibilityUpdater onSetVisibility,
}) {
  return showModalBottomSheet<List<CadObjectPresentation>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ObjectPresentationSheet(
      initialObjects: objects,
      onSetVisibility: onSetVisibility,
    ),
  );
}

class _ObjectPresentationSheet extends StatefulWidget {
  const _ObjectPresentationSheet({
    required this.initialObjects,
    required this.onSetVisibility,
  });

  final List<CadObjectPresentation> initialObjects;
  final ObjectVisibilityUpdater onSetVisibility;

  @override
  State<_ObjectPresentationSheet> createState() => _ObjectPresentationSheetState();
}

class _ObjectPresentationSheetState extends State<_ObjectPresentationSheet> {
  late List<CadObjectPresentation> _objects;
  String? _busyObjectId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _objects = widget.initialObjects;
  }

  List<_ObjectRowData> _orderedRows() {
    final indexById = <String, int>{
      for (var index = 0; index < _objects.length; index++) _objects[index].id: index,
    };
    final children = <String, List<CadObjectPresentation>>{};
    final roots = <CadObjectPresentation>[];

    for (final object in _objects) {
      if (object.parentId.isEmpty || !indexById.containsKey(object.parentId)) {
        roots.add(object);
      } else {
        children.putIfAbsent(object.parentId, () => <CadObjectPresentation>[]).add(object);
      }
    }

    final rows = <_ObjectRowData>[];
    final emitted = <String>{};

    void emit(CadObjectPresentation object, int depth) {
      if (!emitted.add(object.id)) return;
      rows.add(_ObjectRowData(object: object, depth: depth));
      for (final child in children[object.id] ?? const <CadObjectPresentation>[]) {
        emit(child, depth + 1);
      }
    }

    for (final root in roots) {
      emit(root, 0);
    }
    for (final object in _objects) {
      emit(object, 0);
    }
    return rows;
  }

  Future<void> _toggle(CadObjectPresentation object, bool visible) async {
    if (_busyObjectId != null) return;
    setState(() {
      _busyObjectId = object.id;
      _error = null;
    });
    try {
      final updated = await widget.onSetVisibility(object.id, visible);
      if (!mounted) return;
      setState(() => _objects = updated);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? error.code);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyObjectId = null);
    }
  }

  Color _objectColor(BuildContext context, CadObjectPresentation object) {
    if (!object.hasBaseColor || object.baseColor.length != 3) {
      return Theme.of(context).colorScheme.outlineVariant;
    }
    int channel(double value) => (value.clamp(0.0, 1.0) * 255).round();
    return Color.fromARGB(
      255,
      channel(object.baseColor[0]),
      channel(object.baseColor[1]),
      channel(object.baseColor[2]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _orderedRows();
    final visibleCount = _objects.where((object) => object.effectiveVisible && object.hasGeometry).length;
    final geometryCount = _objects.where((object) => object.hasGeometry).length;

    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('对象与可见性', style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        '${_objects.length} 个对象 · $visibleCount / $geometryCount 个几何对象当前可见',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final object = row.object;
                final busy = _busyObjectId == object.id;
                final inheritedHidden = object.inheritedHidden;
                return ListTile(
                  contentPadding: EdgeInsets.only(
                    left: 16 + row.depth * 20.0,
                    right: 12,
                  ),
                  leading: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        object.hasGeometry ? Icons.view_in_ar_outlined : Icons.folder_outlined,
                        color: object.effectiveVisible
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.outline,
                      ),
                      if (object.hasBaseColor)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: _objectColor(context, object),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.surface,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    object.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    inheritedHidden
                        ? '${object.type.isEmpty ? object.id : object.type} · 被父对象隐藏'
                        : (object.type.isEmpty ? object.id : object.type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: busy
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Switch(
                          value: object.visible,
                          onChanged: _busyObjectId == null
                              ? (value) => unawaited(_toggle(object, value))
                              : null,
                        ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Text(
              '开关保存的是对象自身状态；父对象隐藏时，子对象会继承为不可见，但子对象自己的开关不会被改写。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ObjectRowData {
  const _ObjectRowData({required this.object, required this.depth});

  final CadObjectPresentation object;
  final int depth;
}
