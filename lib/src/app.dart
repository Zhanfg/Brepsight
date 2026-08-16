import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
import 'package:cad_engine/src/commands/command_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'files/files_page.dart';
import 'settings/settings_page.dart';
import 'viewer/command_console_sheet.dart';
import 'viewer/viewer_commands.dart';
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
  final CommandRegistry _commandRegistry = createViewerCommandRegistry();
  late final SimpleCommandParser _commandParser = SimpleCommandParser(_commandRegistry);

  int _index = 0;
  String? _openedPath;

  void _openInViewer(String path) {
    setState(() {
      _openedPath = path;
      _index = 1;
    });
  }

  Future<NativeDocumentSummary?> _currentSummary() async {
    final handle = await CadEngine.instance.getCurrentDocumentHandle();
    if (handle == null) return null;
    return CadEngine.instance.getDocumentSummary(handle);
  }

  Future<bool> _confirmLoss({
    required NativeDocumentSummary summary,
    required String format,
    required String action,
  }) async {
    final losses = <String>[];
    if (summary.exactGeometry) {
      losses.add('精确 B-Rep / NURBS、装配层级和可编辑拓扑不会保留在 $format 输出中');
    }
    if (format == 'STL' && summary.hasUv) {
      losses.add('UV 以及依赖 UV 的材质/贴图绑定不会写入 STL');
    }
    if (format == 'STL') {
      losses.add('STL 不保存对象层级、名称和材质结构');
    }
    if (losses.isEmpty) return true;
    if (!mounted) return false;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$action 存在信息损失'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final loss in losses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(loss)),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                const Text('当前原模型不会被修改。'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<CommandResult> _executeCommand(String input) async {
    late final CommandParseResult parsed;
    try {
      parsed = _commandParser.parse(input);
    } on CommandParseException catch (error) {
      return CommandResult(
        state: CommandExecutionState.failed,
        message: error.message,
      );
    }

    try {
      switch (parsed.definition.id) {
        case 'view.fit':
          if (await CadEngine.instance.getCurrentDocumentHandle() == null) {
            return const CommandResult(
              state: CommandExecutionState.failed,
              message: '当前没有打开模型。',
            );
          }
          await CadEngine.instance.fitAll();
          return const CommandResult(
            state: CommandExecutionState.completed,
            message: '已适配全部模型。',
          );

        case 'document.inspect':
          final summary = await _currentSummary();
          if (summary == null) {
            return const CommandResult(
              state: CommandExecutionState.failed,
              message: '当前没有打开模型。',
            );
          }
          if (summary.exactGeometry) {
            return CommandResult(
              state: CommandExecutionState.completed,
              message: '${summary.formatId.toUpperCase()} · Exact B-Rep · '
                  '${summary.rootObjectCount} 根对象 · '
                  '${summary.hierarchyNodeCount} 层级节点 · '
                  '${summary.triangleCount} 显示三角面',
            );
          }
          final inspection = await CadEngine.instance.analyzeCurrentModel();
          return CommandResult(
            state: CommandExecutionState.completed,
            message: '${inspection.closed ? '闭合' : '开放'} · '
                '${inspection.triangleCount} 三角面 · '
                '${inspection.connectedComponentCount} 连通部件 · '
                '${inspection.openEdgeCount} 开边 · '
                '${inspection.nonManifoldEdgeCount} 非流形边',
          );

        case 'document.export':
          final format = parsed.invocation.arguments.single.toUpperCase();
          if (format != 'OBJ' && format != 'STL') {
            return const CommandResult(
              state: CommandExecutionState.failed,
              message: '当前 EXPORT 只接受 OBJ 或 STL。',
            );
          }
          final summary = await _currentSummary();
          if (summary == null) {
            return const CommandResult(
              state: CommandExecutionState.failed,
              message: '当前没有打开模型。',
            );
          }
          if (!await _confirmLoss(
            summary: summary,
            format: format,
            action: '导出',
          )) {
            return const CommandResult(
              state: CommandExecutionState.cancelled,
              message: '已取消导出。',
            );
          }
          final result = await CadEngine.instance.exportCurrentModel(format.toLowerCase());
          return CommandResult(
            state: result == null
                ? CommandExecutionState.cancelled
                : CommandExecutionState.completed,
            message: result == null ? '已取消导出。' : '已导出：${result.displayName}',
          );

        case 'document.split':
          final format = parsed.invocation.arguments.single.toUpperCase();
          if (format != 'OBJ' && format != 'STL') {
            return const CommandResult(
              state: CommandExecutionState.failed,
              message: '当前 SPLIT 只接受 OBJ 或 STL。',
            );
          }
          final summary = await _currentSummary();
          if (summary == null) {
            return const CommandResult(
              state: CommandExecutionState.failed,
              message: '当前没有打开模型。',
            );
          }
          if (summary.formatId != 'obj' && summary.formatId != 'stl') {
            return CommandResult(
              state: CommandExecutionState.failed,
              message: '当前 ${summary.formatId.toUpperCase()} 不能按 Mesh 连通域拆分；'
                  '精确 CAD 拆分会走后续装配/实体 provider。',
            );
          }
          if (!await _confirmLoss(
            summary: summary,
            format: format,
            action: '拆分',
          )) {
            return const CommandResult(
              state: CommandExecutionState.cancelled,
              message: '已取消拆分。',
            );
          }
          final result = await CadEngine.instance.splitCurrentModel(format.toLowerCase());
          return CommandResult(
            state: result == null
                ? CommandExecutionState.cancelled
                : CommandExecutionState.completed,
            message: result == null
                ? '已取消拆分。'
                : '已拆分 ${result.partCount} 个 ${result.formatId.toUpperCase()} 部件。',
          );

        case 'help':
          final lines = _commandRegistry.definitions
              .map((definition) {
                final args = definition.arguments.isEmpty
                    ? ''
                    : ' ${definition.arguments.map((item) => '<${item.name}>').join(' ')}';
                return '${definition.name}$args — ${definition.description}';
              })
              .join('\n');
          return CommandResult(
            state: CommandExecutionState.completed,
            message: lines,
          );
      }
    } on PlatformException catch (error) {
      return CommandResult(
        state: CommandExecutionState.failed,
        message: error.message ?? error.code,
      );
    } catch (error) {
      return CommandResult(
        state: CommandExecutionState.failed,
        message: error.toString(),
      );
    }

    return const CommandResult(
      state: CommandExecutionState.failed,
      message: '命令尚未绑定执行器。',
    );
  }

  Future<void> _openCommandConsole() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => CommandConsoleSheet(
        registry: _commandRegistry,
        execute: _executeCommand,
      ),
    );
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
      floatingActionButton: _index == 1 && _openedPath != null
          ? FloatingActionButton.small(
              tooltip: '命令行',
              onPressed: () => unawaited(_openCommandConsole()),
              child: const Icon(Icons.terminal),
            )
          : null,
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
