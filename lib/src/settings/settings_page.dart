import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.motionViewEnabled = false,
    this.motionSensitivity = 1.0,
    this.onMotionViewChanged,
    this.onMotionSensitivityChanged,
    this.onMotionRecenter,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final bool motionViewEnabled;
  final double motionSensitivity;
  final ValueChanged<bool>? onMotionViewChanged;
  final ValueChanged<double>? onMotionSensitivityChanged;
  final VoidCallback? onMotionRecenter;

  Future<void> _showThirdPartyLicenses(BuildContext context) async {
    final notices = await rootBundle.loadString('THIRD_PARTY_LICENSES.md');
    if (!context.mounted) return;

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
    final theme = Theme.of(context);
    final effectiveBrightness = theme.brightness == Brightness.dark ? '暗色' : '亮色';
    final appearanceInteractive = onThemeModeChanged != null;
    final motionInteractive = onMotionViewChanged != null;

    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('设置'), pinned: true),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 48),
          sliver: SliverList.list(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Text('外观', style: theme.textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('跟随系统'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('亮色'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('暗色'),
                    ),
                  ],
                  selected: {themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: appearanceInteractive
                      ? (selection) => onThemeModeChanged!(selection.first)
                      : null,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text('当前实际显示：$effectiveBrightness'),
                subtitle: const Text(
                  '选择会持久化。模型画布也按亮/暗环境采用独立对比策略，暗色模式不会使用刺眼白底线框。',
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Text('移动端视角', style: theme.textTheme.titleMedium),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.screen_rotation_alt_outlined),
                title: const Text('陀螺仪辅助视角'),
                subtitle: const Text(
                  '仅改变相机，不修改模型。触摸屏幕前会自动撤销运动偏移，保证测量和选择仍使用精确相机状态。',
                ),
                value: motionViewEnabled,
                onChanged: motionInteractive ? onMotionViewChanged : null,
              ),
              if (motionViewEnabled) ...[
                ListTile(
                  leading: const Icon(Icons.speed_outlined),
                  title: const Text('运动灵敏度'),
                  subtitle: Slider(
                    min: 0.35,
                    max: 2.0,
                    divisions: 11,
                    label: '${motionSensitivity.toStringAsFixed(2)}×',
                    value: motionSensitivity.clamp(0.35, 2.0),
                    onChanged: onMotionSensitivityChanged,
                  ),
                  trailing: Text('${motionSensitivity.toStringAsFixed(2)}×'),
                ),
                ListTile(
                  leading: const Icon(Icons.center_focus_strong),
                  title: const Text('重新居中运动视角'),
                  subtitle: const Text('清除当前陀螺仪临时偏移，不改变手势设定的基础视角。'),
                  onTap: onMotionRecenter,
                ),
              ],
              const Divider(),
              const ListTile(
                leading: Icon(Icons.text_fields),
                title: Text('字体'),
                subtitle: Text(
                  '跟随 Android 系统字体，不捆绑额外字体；中文使用系统 CJK fallback。',
                ),
              ),
              const ListTile(
                leading: Icon(Icons.memory_outlined),
                title: Text('渲染后端'),
                subtitle: Text(
                  'Flutter UI + Android SurfaceProducer + C++ / OpenGL ES；工程格式 provider 按当前构建能力加载。',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('第三方许可证'),
                subtitle: const Text('查看随 APK 分发的 OCCT、lib3mf、Assimp、openNURBS 等声明。'),
                onTap: () => _showThirdPartyLicenses(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
