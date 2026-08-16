import 'package:cad_engine/src/commands/command_engine.dart';

CommandRegistry createViewerCommandRegistry() {
  return CommandRegistry()
    ..register(const CommandDefinition(
      id: 'view.fit',
      name: 'FIT',
      aliases: ['F'],
      description: '适配全部模型到当前视图',
    ))
    ..register(const CommandDefinition(
      id: 'document.inspect',
      name: 'INSPECT',
      aliases: ['I'],
      description: '输出当前文档的确定性工程检查摘要',
    ))
    ..register(const CommandDefinition(
      id: 'document.export',
      name: 'EXPORT',
      aliases: ['EX'],
      arguments: [
        CommandArgumentSpec(
          name: 'format',
          kind: CommandInputKind.text,
          description: 'OBJ 或 STL',
        ),
      ],
      description: '按损失提示流程导出 OBJ/STL',
    ))
    ..register(const CommandDefinition(
      id: 'document.split',
      name: 'SPLIT',
      aliases: ['SP'],
      arguments: [
        CommandArgumentSpec(
          name: 'format',
          kind: CommandInputKind.text,
          description: 'OBJ 或 STL',
        ),
      ],
      description: '按连通部件拆分并批量保存',
    ))
    ..register(const CommandDefinition(
      id: 'help',
      name: 'HELP',
      aliases: ['?', 'H'],
      description: '列出当前真正可执行的命令',
    ));
}
