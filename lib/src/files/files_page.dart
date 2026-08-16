import 'package:flutter/material.dart';
import 'package:cad_engine/cad_engine.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key, required this.onOpenInViewer});

  final ValueChanged<String> onOpenInViewer;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  bool _busy = false;
  String? _error;

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await CadEngine.instance.openDocument();
      if (!mounted || path == null) return;
      widget.onOpenInViewer(path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '打开文件失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(
          title: Text('模型文件'),
          pinned: true,
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          sliver: SliverList.list(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('打开本地模型', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text('第一阶段支持通过 Android 系统文件选择器导入模型。不会再内置 Open Sans，中文直接使用系统字体。'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _pickFile,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_to_photos_outlined),
                        label: Text(_busy ? '正在读取…' : '选择 STL / STEP / 其他模型'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _CapabilityCard(),
            ],
          ),
        ),
      ],
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('重构目标', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('STL')),
                Chip(label: Text('STEP / STP')),
                Chip(label: Text('IGES / IGS')),
                Chip(label: Text('OBJ')),
                Chip(label: Text('PLY')),
                Chip(label: Text('glTF / GLB')),
                Chip(label: Text('3DM')),
                Chip(label: Text('DXF')),
                Chip(label: Text('IFC')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
