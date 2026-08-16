# Mobile command workflow

## Goal

Provide a keyboard-first control layer for BrepSight that is fast on phones, familiar to CAD users, and still interoperates with touch selection.

The command line is not an AutoCAD clone. It offers compatibility aliases for common muscle-memory commands where semantics match, while BrepSight adds its own engineering/3D commands.

## Interaction model

```text
viewer
  |
  +-- tap geometry / select objects
  |
  +-- command bar
        > move @sel 10 0 0
        > split @sel connected
        > merge @a @b --mode assembly
```

A command can request additional input and temporarily hand control back to touch selection.

Example:

```text
> measure distance
Select first point:  [tap model]
Select second point: [tap model]
= 42.381 mm
```

## Command parser model

```text
input text
   |
   v
Tokenizer
   |
   v
Alias expansion
   |
   v
Command schema match
   |
   v
Typed argument parser
   |
   +----> request missing interactive input
   |
   v
CommandPlan
   |
   v
Engineering operation / task
```

Commands must compile to typed operations. They must not be passed to a shell or eval-style interpreter.

## Canonical command families

### View / inspection

```text
fit
zoom 2
view top
view iso
section z 20
measure distance
measure angle
measure radius
properties @sel
```

### Selection

```text
select all
select connected
select material "aluminum"
select layer "housing"
select type mesh
clearselect
```

Stable object references should be printable/copyable:

```text
@doc:17/object:42
@sel
@last
```

### Transform

```text
move @sel 10 0 0
rotate @sel z 90deg
scale @sel 0.5
mirror @sel yz
align @a @b center
```

### Composition

```text
merge @a @b --mode assembly
merge @a @b --mode mesh
union @a @b
split @sel connected
split @sel material
split @sel layer
explode @assembly
join @a @b
```

### Mesh / retopology

```text
repair @sel
retopo @sel --faces 20000 --mode quad
retopo @sel --ratio 0.25 --preserve-sharp
unwrap @sel --method auto
packuv @sel
bake normal @high -> @low --size 2048
```

### Conversion / export

```text
convert @doc 3mf
convert @doc glb
export @sel obj /Documents/part.obj
export @doc step
```

Before a lossy conversion, the command engine must show the same capability-loss report as the GUI.

### CAD operations (future exact-geometry path)

```text
box 60 40 8
cylinder d20 h30
fillet @sel r4
chamfer @sel 2
hole @face d4.5 through
pattern @last linear x 4 spacing 20
boolean union @a @b
boolean cut @body @tool
```

These should compile to the same CAD-IR planned for Text-to-CAD.

## Compatibility aliases

Where semantics are genuinely compatible, BrepSight may ship optional aliases inspired by common CAD workflows, for example:

```text
L    -> line
C    -> circle
REC  -> rectangle
M    -> move
CP   -> copy
RO   -> rotate
SC   -> scale
MI   -> mirror
O    -> offset
TR   -> trim
J    -> join
X    -> explode
```

Aliases must be configurable and visible in autocomplete. Canonical BrepSight command names remain stable even if compatibility aliases change.

## Mobile-specific syntax

The parser should tolerate phone keyboard conventions:

```text
60x40x8
60×40×8
20mm
2.5cm
90deg
90°
1/4in
```

It should also support commas/spaces where unambiguous:

```text
move @sel 10,0,0
move @sel 10 0 0
```

## Autocomplete

Autocomplete should rank:

1. exact command/alias prefix;
2. context-valid commands;
3. recent commands;
4. referenced objects/materials/layers;
5. parameter names.

Example:

```text
> ret
  RETOPO    Retopologize selected mesh
  RETRY     Retry last failed task
```

## Command history

Store structured history, not just strings:

```text
CommandHistoryEntry
- rawText
- parsedCommandId
- resolved object references
- parameters
- timestamp
- result/task id
- undo transaction id
```

This allows replay even when aliases are later changed.

## Safety

- No shell execution.
- No arbitrary scripting in the default command bar.
- Machine/toolpath commands are inspect/export only unless a future separately-authorized control product exists.
- Destructive operations use document transactions and support undo when practical.
- Long operations return a ModelTask ID and may continue in the background foreground-service host.

## Relationship to Text-to-CAD

The command engine is the deterministic low-level language for future natural-language generation:

```text
"move the bracket 10 mm upward"
              |
              v
Command/CAD-IR operation
MOVE @bracket 0 0 10mm
```

This lets AI-generated intent remain inspectable, replayable and manually correctable.
