# Agent Instructions — miaou-composer

## Running and Testing TUI Apps

**This project has its own MCP server registered in `.mcp.json`.**
Use its headless tools to run and inspect TUI binaries — do NOT invoke them directly (they require a real terminal and will crash otherwise).

### The MCP server tools are available as:
- `mcp__miaou-composer__headless_init`
- `mcp__miaou-composer__headless_key`
- `mcp__miaou-composer__headless_render`
- `mcp__miaou-composer__headless_click`
- `mcp__miaou-composer__headless_tick`
- `mcp__miaou-composer__headless_stop`

### Workflow
1. Build: `opam exec -- dune build`
2. `headless_init` with `binary = "/home/mathias/dev/miaou-composer/_build/default/bin/designer/main.exe"`
3. `headless_render` to capture the screen
4. `headless_key` to send keystrokes
5. `headless_stop` when done

`MIAOU_DRIVER=headless` is set automatically by `headless_init`.

### Available binaries
| Binary | Description |
|--------|-------------|
| `_build/default/bin/designer/main.exe` | OCaml Page Designer TUI |
| `_build/default/bin/json_runner/main.exe pages/composer.json` | JSON-driven composer |
| `_build/default/bin/mcp_server/main.exe` | MCP server itself |

## Build & Test

```bash
opam exec -- dune build   # build everything
opam exec -- dune test    # run all tests
```

## Key Directories

| Path | Contents |
|------|----------|
| `lib/compositor/` | Core compositor engine (Page, Layout_tree, Wiring, Action…) |
| `lib/bridge/` | JSON codecs (Page_codec, Action_codec, Widget_factory…) |
| `bin/designer/` | OCaml Page Designer TUI |
| `bin/json_runner/` | JSON-driven page runner |
| `bin/mcp_server/` | MCP server |
| `pages/` | JSON page definitions (`composer.json`) |
| `test/` | Alcotest test suites |
