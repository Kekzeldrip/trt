# TRT – Rotation Helper

A World of Warcraft addon that provides rotation recommendations based on
SimulationCraft Action Priority Lists (APL).

## Features

- **SimC APL Engine** – Parses and evaluates SimulationCraft APL syntax in
  real-time using live game state.
- **Minimal UI Overlay** – Displays the recommended next ability as an icon on
  screen. Movable and lockable.
- **Enhancement Shaman** – Ships with the full SimC APL for Enhancement Shaman
  (spec ID 263).
- **Extensible** – Adding a new class/spec only requires a new Lua file that
  registers spell IDs and an APL text block.

## Installation

1. Copy the `TRT` folder into your WoW `Interface/AddOns/` directory.
2. Restart WoW or type `/reload` in the chat.
3. Log in on an Enhancement Shaman to see the rotation helper.

## Slash Commands

| Command       | Description                          |
|---------------|--------------------------------------|
| `/trt`        | Toggle the helper on/off             |
| `/trt on`     | Enable                               |
| `/trt off`    | Disable                              |
| `/trt lock`   | Lock/unlock the overlay position     |
| `/trt reset`  | Reset overlay to default position    |
| `/trt debug`  | Toggle debug output in chat          |

## Architecture

```
TRT/
├── TRT.toc                         # Addon manifest
├── Core.lua                        # Event handling, initialization, slash commands
├── API.lua                         # WoW API abstraction (buffs, CDs, talents, etc.)
├── Spells.lua                      # Spell registry and rotation registration
├── APLParser.lua                   # SimC APL text → parsed action list with AST
├── Conditions.lua                  # AST expression evaluator against game state
├── Engine.lua                      # Main tick loop: evaluate APL → recommend ability
├── UI.lua                          # On-screen icon overlay
├── Rotations/
│   └── ShamanEnhancement.lua       # Enhancement Shaman spell IDs + full SimC APL
└── Tests/
    └── test_parser.lua             # Offline Lua tests for the APL parser
```

### How it Works

1. **APLParser** reads SimC APL text and produces a table of action entries.
   Each entry's `if` condition is parsed into an AST (Abstract Syntax Tree).
2. **Conditions** evaluates AST nodes at runtime by querying **API** (the game
   state layer) for buff stacks, cooldowns, talent selections, etc.
3. **Engine** iterates the default action list every 100 ms while in combat.
   `call_action_list` entries recurse into sub-lists (single target, AoE, etc.)
   The first action whose condition passes *and* whose spell is usable is
   returned as the recommendation.
4. **UI** displays the recommended spell icon on screen.

### Adding a New Spec

Create a file under `Rotations/` (e.g. `WarlockDestruction.lua`):

```lua
local _, TRT = ...

local SPELLS   = { chaos_bolt = 116858, ... }
local BUFFS    = { backdraft = 196406, ... }
local DEBUFFS  = { immolate = 157736, ... }

local APL_TEXT = [[
actions=chaos_bolt,if=buff.backdraft.up
actions+=/incinerate
]]

local apl = TRT.APLParser:ParseAPL(APL_TEXT)

TRT:RegisterRotation("WARLOCK", 267, {
    name     = "Destruction Warlock (SimC)",
    apl      = apl,
    spellMap = { chaos_bolt = 116858, incinerate = 29722 },
    buffMap  = { backdraft = 196406 },
    debuffMap = { immolate = 157736 },
    talentMap = {},
    dotMap    = { immolate = 157736 },
})
```

Then add the file to `TRT.toc`.

## Running Tests

```bash
lua TRT/Tests/test_parser.lua
```

## License

Open source – free to use, modify and distribute.
