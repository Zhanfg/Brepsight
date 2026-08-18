import 'package:flutter/material.dart';

import 'files/files_page.dart';
import 'settings/settings_page.dart';
import 'viewer/viewer_workspace_page.dart';

class BrepSightAppV01 extends StatelessWidget {
  const BrepSightAppV01({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        ),
      ),
      themeMode: ThemeMode.system,
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

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
    final pages = <Widget>[
      FilesPage(onOpenInViewer: _openModel),
      ViewerWorkspacePage(
        modelPath: _openedPath,
        onExitViewer: _leaveViewer,
      ),
      const SettingsPage(),
    ];
    final immersiveViewer = _index == 1 && _openedPath != null;

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
