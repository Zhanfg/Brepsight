import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _showEdges = true;
  bool _autoFit = true;
  bool _showFps = false;

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
              subtitle: Text('Flutter UI + Android SurfaceProducer + C++ / OpenGL ES + OpenCASCADE。'),
            ),
          ],
        ),
      ],
    );
  }
}
