import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'local_annotations.dart';

class AnnotationComposeRequest {
  const AnnotationComposeRequest({
    required this.text,
    required this.includeScreenshot,
  });

  final String text;
  final bool includeScreenshot;
}

String annotationAnchorLabel(LocalModelAnnotation annotation) {
  if (!annotation.hasAnchor) return '模型级';
  return switch (annotation.anchorKind) {
    'vertex' => '顶点锚点',
    'edge' => '边锚点',
    'body' => '对象锚点',
    _ => '面锚点',
  };
}

String _timestampLabel(int millis) {
  final value = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

Uint8List? _decodeScreenshot(String? encoded) {
  if (encoded == null || encoded.isEmpty) return null;
  try {
    return base64Decode(encoded);
  } on FormatException {
    return null;
  }
}

Future<AnnotationComposeRequest?> showAnnotationComposer({
  required BuildContext context,
  required bool anchored,
}) async {
  final controller = TextEditingController();
  var includeScreenshot = false;
  try {
    return await showModalBottomSheet<AnnotationComposeRequest>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('新建本地批注', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                anchored
                    ? '当前选择会作为稳定几何锚点保存。'
                    : '当前没有选择，将保存为模型级批注。',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 1200,
                minLines: 3,
                maxLines: 7,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '批注内容',
                  hintText: '记录检查结论、修改意见或装配说明…',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeScreenshot,
                onChanged: (value) {
                  includeScreenshot = value ?? false;
                  update(() {});
                },
                title: const Text('附加当前视图截图'),
                subtitle: const Text('保存低分辨率 PNG 缩略图，仅存储在本机批注数据中。'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(
                    sheetContext,
                    AnnotationComposeRequest(
                      text: text,
                      includeScreenshot: includeScreenshot,
                    ),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存批注'),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

class LocalAnnotationSheet extends StatelessWidget {
  const LocalAnnotationSheet({
    super.key,
    required this.annotations,
    required this.onAdd,
    required this.onOpen,
    required this.onDelete,
  });

  final List<LocalModelAnnotation> annotations;
  final VoidCallback onAdd;
  final ValueChanged<LocalModelAnnotation> onOpen;
  final ValueChanged<LocalModelAnnotation> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: Text('本地批注 · ${annotations.length}'),
              subtitle: const Text('文本、几何锚点和可选截图只保存在此设备。'),
              trailing: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(context);
                  onAdd();
                },
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('新建'),
              ),
            ),
            const Divider(height: 1),
            if (annotations.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 30, 24, 36),
                child: Column(
                  children: [
                    Icon(Icons.speaker_notes_off_outlined, size: 38),
                    SizedBox(height: 10),
                    Text('当前模型还没有本地批注'),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                  itemCount: annotations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final annotation = annotations[index];
                    final screenshot = _decodeScreenshot(annotation.screenshotPngBase64);
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          onOpen(annotation);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (screenshot != null) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    screenshot,
                                    width: 84,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const SizedBox(
                                      width: 84,
                                      height: 64,
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(annotationAnchorLabel(annotation)),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _timestampLabel(annotation.createdAtMillis),
                                            textAlign: TextAlign.end,
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      annotation.text,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (annotation.featureStableId != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        annotation.featureStableId!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '删除批注',
                                onPressed: () {
                                  Navigator.pop(context);
                                  onDelete(annotation);
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
