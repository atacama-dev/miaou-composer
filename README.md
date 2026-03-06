miaou-composer
==============

A live dynamic UI compositor for [Miaou](https://github.com/trilitech/miaou) TUI applications.

Build JSON-described pages at runtime, wire widgets together, and drive them programmatically via an MCP server — no recompilation required.

Features
--------

- **Compositor core** — runtime page model (layout tree, widget store, focus ring, wirings, actions)
- **JSON bridge** — encode/decode full pages and actions to/from JSON (`Page_codec`, `Widget_factory`, `Action_codec`)
- **MCP server** — expose TUI pages as Model Context Protocol tools; drive them headlessly from any MCP client
- **JSON runner** — run a `pages/*.json` page definition directly in the terminal or via the Web Viewer
- **Page Designer TUI** — interactive OCaml TUI for editing pages live with a properties pane and preview

Architecture
------------

```
lib/compositor/   Core engine — Page, Layout_tree, Wiring, Focus_manager, Catalog, Validator
lib/bridge/       JSON codecs — Page_codec, Action_codec, Widget_factory, Tool_codec
lib/export/       Serialisation helpers
bin/designer/     Interactive Page Designer TUI
bin/json_runner/  JSON-driven page runner (terminal + web viewer)
bin/mcp_server/   MCP server binary
bin/canvas_tool/  Stateful canvas helper (used by the MCP server)
pages/            JSON page definitions
test/             Alcotest test suites
```

Install from source
-------------------

**Prerequisites**

- OCaml >= 5.2 (5.3.x recommended) and opam
- miaou >= 0.4.2 — pin before installing:

```sh
# Pin the miaou packages (not yet in the opam repository)
opam pin add miaou-core    git+https://github.com/trilitech/miaou.git --no-action
opam pin add miaou-runner  git+https://github.com/trilitech/miaou.git --no-action
opam pin add miaou-registry git+https://github.com/trilitech/miaou.git --no-action

# Pin the ppx build dependencies
opam pin add ppx_forbid  git+https://github.com/atacama-dev/ppx_forbid.git --no-action
opam pin add ppx_enforce git+https://github.com/atacama-dev/ppx_forbid.git --no-action

# Install all dependencies
opam install --deps-only -y .

# Build
eval $(opam env)
dune build @all

# Run tests
dune runtest

# Install binaries
dune install
```

Binaries installed
------------------

| Binary | Description |
|--------|-------------|
| `miaou-composer-designer` | Interactive Page Designer TUI |
| `miaou-composer-json` | JSON-driven page runner |
| `miaou-composer-mcp` | MCP server |

Running
-------

**Page Designer TUI**
```sh
miaou-composer-designer
```

**JSON runner** (runs a page definition from a JSON file)
```sh
miaou-composer-json pages/composer.json
```

**MCP server** (stdio transport, for use with an MCP client)
```sh
miaou-composer-mcp
```

Configure your MCP client to launch `miaou-composer-mcp` as a subprocess. It exposes tools for initialising headless TUI sessions, sending keys, rendering frames, and stopping sessions.

License
-------

GPL-3.0-or-later — Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>
