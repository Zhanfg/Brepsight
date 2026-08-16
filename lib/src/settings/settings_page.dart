import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _showEdges = true;
  bool _autoFit = true;
  bool _showFps = false;

  Future<void> _showThirdPartyLicenses() async {
    final notices = await rootBundle.loadString('THIRD_PARTY_LICENSES.md');
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('第三方许可证'),
        content: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SelectableText(notices),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('设置'), pinned: true),
        SliverList.list(
          children: [
            SwitchListTile(
              title: const Text('默认显示边线'),
              subtitle: const Text('实体模式下保留轮廓与拓扑边。'),
              value: _showEdges,
              onChanged: (value) => setState(() => _showEdges = value),
            ),
            SwitchListTile(
              title: const Text('打开后自动适配视图'),
              value: _autoFit,
              onChanged: (value) => setState(() => _autoFit = value),
            ),
            SwitchListTile(
              title: const Text('显示帧率调试信息'),
              value: _showFps,
              onChanged: (value) => setState(() => _showFps = value),
            ),
            const ListTile(
              title: Text('字体'),
              subtitle: Text('跟随 Android 系统字体，不再捆绑 Open Sans；中文可直接使用系统 CJK fallback。'),
            ),
            const ListTile(
              title: Text('渲染后端'),
              subtitle: Text('Flutter UI + Android SurfaceProducer + C++ / OpenGL ES；精确 CAD 与 3MF provider 按构建能力可选启用。'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('第三方许可证'),
              subtitle: const Text('查看随 APK 分发的 OCCT、lib3mf 等第三方依赖声明。'),
              onTap: _showThirdPartyLicenses,
            ),
          ],
        ),
      ],
    );
  }
}
