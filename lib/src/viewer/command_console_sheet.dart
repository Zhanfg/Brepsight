import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
import 'package:flutter/material.dart';

class CommandConsoleSheet extends StatefulWidget {
  const CommandConsoleSheet({
    super.key,
    required this.registry,
    required this.execute,
  });

  final CommandRegistry registry;
  final Future<CommandResult> Function(String input) execute;

  @override
  State<CommandConsoleSheet> createState() => _CommandConsoleSheetState();
}

class _CommandConsoleSheetState extends State<CommandConsoleSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<_ConsoleEntry> _history = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Iterable<CommandDefinition> get _suggestions {
    final raw = _controller.text.trimLeft();
    if (raw.contains(RegExp(r'\s'))) return const <CommandDefinition>[];
    return widget.registry.suggest(raw).take(6);
  }

  Future<void> _submit([String? forced]) async {
    if (_running) return;
    final input = (forced ?? _controller.text).trim();
    if (input.isEmpty) return;

    setState(() {
      _running = true;
      _history.add(_ConsoleEntry(input: input));
      _controller.clear();
    });

    try {
      final result = await widget.execute(input);
      if (!mounted) return;
      setState(() {
        _history[_history.length - 1] = _history.last.copyWith(
          result: result.message.isEmpty ? result.state.name : result.message,
          failed: result.state == CommandExecutionState.failed,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _history[_history.length - 1] = _history.last.copyWith(
          result: error.toString(),
          failed: true,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _running = false);
        _focusNode.requestFocus();
      }
    }
  }

  void _complete(CommandDefinition definition) {
    final suffix = definition.arguments.isEmpty ? '' : ' ';
    _controller.value = TextEditingValue(
      text: '${definition.name}$suffix',
      selection: TextSelection.collapsed(offset: definition.name.length + suffix.length),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = _suggestions.toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.66,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.terminal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BrepSight 命令', style: theme.textTheme.titleLarge),
                        Text(
                          '确定性命令，不执行 shell。输入 HELP 查看当前可用命令。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _history.isEmpty
                    ? Center(
                        child: Text(
                          '例如：FIT · INSPECT · EXPORT OBJ · SPLIT STL',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        itemCount: _history.length,
                        itemBuilder: (context, reverseIndex) {
                          final entry = _history[_history.length - 1 - reverseIndex];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText('> ${entry.input}'),
                                if (entry.result != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3, left: 12),
                                    child: SelectableText(
                                      entry.result!,
                                      style: TextStyle(
                                        color: entry.failed ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final definition in suggestions) ...[
                        ActionChip(
                          label: Text(definition.name),
                          tooltip: definition.description,
                          onPressed: () => _complete(definition),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: !_running,
                textInputAction: TextInputAction.send,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  prefixText: '> ',
                  hintText: '输入命令',
                  border: const OutlineInputBorder(),
                  suffixIcon: _running
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: '执行',
                          onPressed: () => unawaited(_submit()),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                ),
                onSubmitted: (_) => unawaited(_submit()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsoleEntry {
  const _ConsoleEntry({required this.input, this.result, this.failed = false});

  final String input;
  final String? result;
  final bool failed;

  _ConsoleEntry copyWith({String? result, bool? failed}) => _ConsoleEntry(
        input: input,
        result: result ?? this.result,
        failed: failed ?? this.failed,
      );
}
