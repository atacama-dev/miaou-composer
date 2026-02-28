# Quickstart: Miaou Composer

**Branch**: `001-miaou-composer` | **Date**: 2026-03-01

## Prerequisites

- OCaml 5.x with opam
- `miaou-core` installed (opam package)
- `mcp`, `mcp-eio`, `mcp-sdk` installed (opam packages)
- `yojson` installed (opam package)

## Project Setup

```bash
cd miaou-composer
opam install . --deps-only
dune build
```

## Running the MCP Server

```bash
dune exec miaou-composer-mcp
```

The server reads JSON-RPC from stdin and writes responses to stdout. Connect it to any MCP client (Claude, etc.) via stdio transport.

## Quick Example: Build a Form via MCP

### 1. Create a page with a simple form

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"miaou/create_page","arguments":{
  "page_id": "login",
  "size": {"rows": 12, "cols": 40},
  "layout": {
    "type": "flex", "direction": "column", "gap": 1,
    "padding": {"top": 1, "left": 2, "right": 2, "bottom": 1},
    "children": [
      {"type": "textbox", "id": "user", "title": "Username", "basis": "auto"},
      {"type": "textbox", "id": "pass", "title": "Password", "mask": true, "basis": "auto"},
      {"type": "button", "id": "login_btn", "label": "Login", "basis": "auto"}
    ]
  },
  "focus_ring": ["user", "pass", "login_btn"]
}}}
```

### 2. Type into the username field

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"miaou/send_keys","arguments":{
  "page_id": "login",
  "keys": ["a", "d", "m", "i", "n"]
}}}
```

### 3. Tab to password, type, tab to button

```json
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"miaou/send_keys","arguments":{
  "page_id": "login",
  "keys": ["Tab", "s", "e", "c", "r", "e", "t", "Tab"]
}}}
```

### 4. Wire the login button to emit an event

```json
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"miaou/wire","arguments":{
  "page_id": "login",
  "source": "login_btn",
  "event": "click",
  "action": {"type": "emit", "event": "login_submitted"}
}}}
```

### 5. Press Enter to trigger the button

```json
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"miaou/send_key","arguments":{
  "page_id": "login",
  "key": "Enter"
}}}
```

Response includes emitted event with form state:
```json
{
  "render": "...",
  "events": [{
    "name": "login_submitted",
    "state": {
      "user": {"type": "textbox", "state": {"text": "admin"}},
      "pass": {"type": "textbox", "state": {"text": "secret"}},
      "login_btn": {"type": "button", "state": {"label": "Login"}}
    }
  }]
}
```

### 6. Query individual widget state

```json
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"miaou/query_widget","arguments":{
  "page_id": "login",
  "widget_id": "user"
}}}
```

### 7. Export the page

```json
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"miaou/export_json","arguments":{
  "page_id": "login"
}}}
```

## Development

### Build

```bash
dune build
```

### Test

```bash
dune test
```

### Project Structure

```
lib/
├── compositor/        # Core compositor engine
│   ├── widget_box.ml  # Existential widget boxing
│   ├── layout_tree.ml # Mutable layout tree
│   ├── wiring.ml      # Event→action wiring table
│   ├── page.ml        # Page state management
│   ├── session.ml     # Multi-page session
│   ├── catalog.ml     # Widget catalog metadata
│   └── validator.ml   # Page definition validation
├── bridge/            # JSON↔OCaml conversion
│   ├── widget_factory.ml  # JSON → widget_box constructors
│   ├── layout_codec.ml    # JSON ↔ layout_tree serialization
│   ├── action_codec.ml    # JSON ↔ action serialization
│   └── page_codec.ml      # JSON ↔ page definition
└── export/            # Export functionality
    └── json_export.ml # Live page → JSON document

bin/
└── mcp_server/        # MCP server binary
    ├── main.ml        # Entry point, stdio transport
    └── tools.ml       # MCP tool definitions and handlers

test/
├── test_widget_box.ml
├── test_layout_tree.ml
├── test_wiring.ml
├── test_page.ml
├── test_validator.ml
├── test_bridge.ml
└── test_mcp_tools.ml
```
