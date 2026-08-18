import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'files/files_page.dart';
import 'settings/settings_page.dart';
import 'viewer/motion_view_host.dart';
import 'viewer/viewer_workspace_page.dart';

class BrepSightAppV01 extends StatefulWidget {
  const BrepSightAppV01({super.key});

  @override
  State<BrepSightAppV01> createState() => _BrepSightAppV01State();
}

class _BrepSightAppV01State extends State<BrepSightAppV01> {
  static const _themeKey = 'appearance.themeMode';
  static const _motionEnabledKey = 'viewer.motion.enabled';
  static const _motionSensitivityKey = 'viewer.motion.sensitivity';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  ThemeMode _themeMode = ThemeMode.system;
  bool _motionViewEnabled = false;
  double _motionSensitivity = 1.0;
  int _motionRecenterToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    final themeName = await _preferences.getString(_themeKey);
    final motionEnabled = await _preferences.getBool(_motionEnabledKey);
    final motionSensitivity = await _preferences.getDouble(_motionSensitivityKey);
    if (!mounted) return;
    setState(() {
      _themeMode = switch (themeName) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _motionViewEnabled = motionEnabled ?? false;
      _motionSensitivity = (motionSensitivity ?? 1.0).clamp(0.35, 2.0);
    });
  }

  Future<void> _setThemeMode(ThemeMode value) async {
    setState(() => _themeMode = value);
    await _preferences.setString(_themeKey, value.name);
  }

  Future<void> _setMotionViewEnabled(bool value) async {
    setState(() => _motionViewEnabled = value);
    await _preferences.setBool(_motionEnabledKey, value);
  }

  Future<void> _setMotionSensitivity(double value) async {
    final normalized = value.clamp(0.35, 2.0).toDouble();
    setState(() => _motionSensitivity = normalized);
    await _preferences.setDouble(_motionSensitivityKey, normalized);
  }

  void _recenterMotionView() {
    setState(() => _motionRecenterToken++);
  }

  void _motionSensorUnavailable() {
    if (_motionViewEnabled) {
      unawaited(_setMotionViewEnabled(false));
    }
    _messengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('当前设备未提供可用的陀螺仪，已关闭运动视角。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'BrepSight',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF455D83),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F5F8),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 1,
        ),
        navigationBarTheme: const NavigationBarThemeData(height: 72),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF91A9D0),
          brightness: Brightness.dark,
          surface: const Color(0xFF15191F),
        ),
        scaffoldBackgroundColor: const Color(0xFF101419),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 1,
        ),
        navigationBarTheme: const NavigationBarThemeData(height: 72),
      ),
      themeMode: _themeMode,
      home: _AppShell(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        motionViewEnabled: _motionViewEnabled,
        motionSensitivity: _motionSensitivity,
        motionRecenterToken: _motionRecenterToken,
        onMotionViewChanged: _setMotionViewEnabled,
        onMotionSensitivityChanged: _setMotionSensitivity,
        onMotionRecenter: _recenterMotionView,
        onMotionSensorUnavailable: _motionSensorUnavailable,
      ),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell({
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.motionViewEnabled,
    required this.motionSensitivity,
    required this.motionRecenterToken,
    required this.onMotionViewChanged,
    required this.onMotionSensitivityChanged,
    required this.onMotionRecenter,
    required this.onMotionSensorUnavailable,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool motionViewEnabled;
  final double motionSensitivity;
  final int motionRecenterToken;
  final ValueChanged<bool> onMotionViewChanged;
  final ValueChanged<double> onMotionSensitivityChanged;
  final VoidCallback onMotionRecenter;
  final VoidCallback onMotionSensorUnavailable;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _index = 0;
  String? _openedPath;

  void _openModel(String path) {
    setState(() {
      _openedPath = path;
      _index = 1;
    });
  }

  void _leaveViewer() {
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    final immersiveViewer = _index == 1 && _openedPath != null;
    final viewer = MotionViewHost(
      enabled: immersiveViewer && widget.motionViewEnabled,
      sensitivity: widget.motionSensitivity,
      recenterToken: widget.motionRecenterToken,
      onSensorUnavailable: widget.onMotionSensorUnavailable,
      child: ViewerWorkspacePage(
        modelPath: _openedPath,
        onExitViewer: _leaveViewer,
      ),
    );

    final pages = <Widget>[
      FilesPage(onOpenInViewer: _openModel),
      viewer,
      SettingsPage(
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        motionViewEnabled: widget.motionViewEnabled,
        motionSensitivity: widget.motionSensitivity,
        onMotionViewChanged: widget.onMotionViewChanged,
        onMotionSensitivityChanged: widget.onMotionSensitivityChanged,
        onMotionRecenter: widget.onMotionRecenter,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: immersiveViewer
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: '文件',
                ),
                NavigationDestination(
                  icon: Icon(Icons.view_in_ar_outlined),
                  selectedIcon: Icon(Icons.view_in_ar),
                  label: '查看',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: '设置',
                ),
              ],
            ),
    );
  }
}
