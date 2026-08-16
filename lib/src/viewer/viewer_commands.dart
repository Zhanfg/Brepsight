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
      id: 'view.perspective',
      name: 'PERSPECTIVE',
      aliases: ['PERSP'],
      description: '切换为透视投影',
    ))
    ..register(const CommandDefinition(
      id: 'view.orthographic',
      name: 'ORTHO',
      aliases: ['ORTHOGRAPHIC'],
      description: '切换为正交投影',
    ))
    ..register(const CommandDefinition(
      id: 'view.shaded',
      name: 'SHADE',
      aliases: ['SHADED'],
      description: '实体着色显示',
    ))
    ..register(const CommandDefinition(
      id: 'view.shaded_edges',
      name: 'EDGES',
      aliases: ['SHADEDEDGES'],
      description: '着色并显示三角边线',
    ))
    ..register(const CommandDefinition(
      id: 'view.wireframe',
      name: 'WIRE',
      aliases: ['WI', 'WIREFRAME'],
      description: '切换为线框显示',
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
      description: '按现有损失提示流程导出 OBJ/STL',
    ))
    ..register(const CommandDefinition(
      id: 'help',
      name: 'HELP',
      aliases: ['?', 'H'],
      description: '列出当前真正可执行的命令',
    ));
}
