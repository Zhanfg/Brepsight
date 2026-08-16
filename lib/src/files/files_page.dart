import 'package:cad_engine/cad_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key, required this.onOpenInViewer});

  final ValueChanged<String> onOpenInViewer;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  bool _busy = false;
  String? _busyLabel;
  String? _error;
  String? _message;

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _busyLabel = '正在导入…';
      _error = null;
      _message = null;
    });
    try {
      final path = await CadEngine.instance.openDocument();
      if (!mounted || path == null) return;
      widget.onOpenInViewer(path);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = '打开文件失败：${error.message ?? error.code}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '打开文件失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _mergeFiles() async {
    setState(() {
      _busy = true;
      _busyLabel = '正在合并…';
      _error = null;
      _message = null;
    });
    try {
      final result = await CadEngine.instance.mergeDocuments();
      if (!mounted) return;
      if (result == null) {
        setState(() => _message = '已取消多模型合并');
        return;
      }
      setState(() => _message = '已合并 ${result.sourceCount} 个模型');
      widget.onOpenInViewer(result.outputPath);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = '合并失败：${error.message ?? error.code}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '合并失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(
          title: Text('工程模型'),
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('打开与组合', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        '当前 native 主链已打通 STL 与 OBJ：可直接查看、检查、拆分、合并并重新导出。STEP、3DM、DXF、3MF 等按各自 provider 继续接入。',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _pickFile,
                        icon: _busy && _busyLabel == '正在导入…'
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.folder_open_outlined),
                        label: Text(_busy && _busyLabel == '正在导入…' ? _busyLabel! : '打开 STL / OBJ'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _mergeFiles,
                        icon: _busy && _busyLabel == '正在合并…'
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.layers_outlined),
                        label: Text(_busy && _busyLabel == '正在合并…' ? _busyLabel! : '合并多个 STL / OBJ'),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Mesh Merge 按各文件原坐标合并，不执行实体布尔并集。只有全部输入都带完整 UV 时，合并结果才保留 UV。',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(_message!),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前可用', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(avatar: Icon(Icons.check, size: 16), label: Text('STL')),
                Chip(avatar: Icon(Icons.check, size: 16), label: Text('OBJ + UV')),
                Chip(label: Text('查看 / 线框')),
                Chip(label: Text('模型检查')),
                Chip(label: Text('格式中转')),
                Chip(label: Text('连通部件拆分')),
                Chip(label: Text('多模型合并')),
              ],
            ),
            const SizedBox(height: 18),
            Text('接入中', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('STEP / STP')),
                Chip(label: Text('3MF')),
                Chip(label: Text('3DM / Rhino 8')),
                Chip(label: Text('DXF / DWG provider')),
                Chip(label: Text('glTF / GLB')),
                Chip(label: Text('FCStd')),
                Chip(label: Text('VTK / CAE')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
