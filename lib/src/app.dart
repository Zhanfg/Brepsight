import 'package:flutter/material.dart';

import 'files/files_page.dart';
import 'settings/settings_page.dart';
import 'viewer/viewer_page.dart';

class BrepSightApp extends StatelessWidget {
  const BrepSightApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F6BED),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF9DB0FF),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BrepSight',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        visualDensity: VisualDensity.standard,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        visualDensity: VisualDensity.standard,
      ),
      home: const CadShell(),
    );
  }
}

class CadShell extends StatefulWidget {
  const CadShell({super.key});

  @override
  State<CadShell> createState() => _CadShellState();
}

class _CadShellState extends State<CadShell> {
  int _index = 0;
  String? _openedPath;

  void _openInViewer(String path) {
    setState(() {
      _openedPath = path;
      _index = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      FilesPage(onOpenInViewer: _openInViewer),
      ViewerPage(modelPath: _openedPath),
      const SettingsPage(),
    ];

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_open),
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
