(** MCP tool definitions. Each tool has a name, description, and input schema.
*)

type tool_def = {
  name : string;
  description : string;
  input_schema : Yojson.Safe.t;
}

let string_prop ~desc =
  `Assoc [ ("type", `String "string"); ("description", `String desc) ]

let int_prop ~desc =
  `Assoc [ ("type", `String "integer"); ("description", `String desc) ]

let bool_prop ~desc =
  `Assoc [ ("type", `String "boolean"); ("description", `String desc) ]

let object_prop ~desc =
  `Assoc [ ("type", `String "object"); ("description", `String desc) ]

let array_prop ~desc ~items =
  `Assoc
    [
      ("type", `String "array"); ("description", `String desc); ("items", items);
    ]

let make_schema ~properties ~required =
  `Assoc
    [
      ("type", `String "object");
      ("properties", `Assoc properties);
      ("required", `List (List.map (fun s -> `String s) required));
    ]

let all_tools () =
  [
    {
      name = "create_page";
      description = "Create a new page from a JSON page definition";
      input_schema =
        make_schema
          ~properties:
            [ ("page_def", object_prop ~desc:"Full page definition JSON") ]
          ~required:[ "page_def" ];
    };
    {
      name = "delete_page";
      description = "Delete a page by ID";
      input_schema =
        make_schema
          ~properties:[ ("page_id", string_prop ~desc:"Page ID to delete") ]
          ~required:[ "page_id" ];
    };
    {
      name = "list_pages";
      description = "List all active pages";
      input_schema = make_schema ~properties:[] ~required:[];
    };
    {
      name = "add_widget";
      description = "Add a widget to an existing page";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ( "widget_def",
                object_prop ~desc:"Widget JSON definition with type and id" );
              ( "path",
                array_prop ~desc:"Path indices to parent container"
                  ~items:(`Assoc [ ("type", `String "integer") ]) );
              ("position", int_prop ~desc:"Insert position within parent");
            ]
          ~required:[ "page_id"; "widget_def" ];
    };
    {
      name = "remove_widget";
      description = "Remove a widget from a page";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ("widget_id", string_prop ~desc:"Widget ID to remove");
            ]
          ~required:[ "page_id"; "widget_id" ];
    };
    {
      name = "update_widget";
      description = "Update a widget's state with a JSON patch";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ("widget_id", string_prop ~desc:"Widget ID to update");
              ("patch", object_prop ~desc:"JSON patch to apply");
            ]
          ~required:[ "page_id"; "widget_id"; "patch" ];
    };
    {
      name = "query_widget";
      description = "Query a widget's current state";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ("widget_id", string_prop ~desc:"Widget ID to query");
            ]
          ~required:[ "page_id"; "widget_id" ];
    };
    {
      name = "add_wiring";
      description = "Wire a widget event to an action";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ("source", string_prop ~desc:"Source widget ID");
              ("event", string_prop ~desc:"Event name (e.g. 'click', 'toggle')");
              ("action", object_prop ~desc:"Action definition JSON");
            ]
          ~required:[ "page_id"; "source"; "event"; "action" ];
    };
    {
      name = "remove_wiring";
      description = "Remove a wiring by source and event";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ("source", string_prop ~desc:"Source widget ID");
              ("event", string_prop ~desc:"Event name");
            ]
          ~required:[ "page_id"; "source"; "event" ];
    };
    {
      name = "list_wirings";
      description = "List all wirings on a page";
      input_schema =
        make_schema
          ~properties:[ ("page_id", string_prop ~desc:"Target page ID") ]
          ~required:[ "page_id" ];
    };
    {
      name = "send_key";
      description = "Send a key press to the focused widget on a page";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ("key", string_prop ~desc:"Key name (e.g. 'Enter', 'Tab', 'a')");
            ]
          ~required:[ "page_id"; "key" ];
    };
    {
      name = "render";
      description = "Render a page and return the text frame";
      input_schema =
        make_schema
          ~properties:[ ("page_id", string_prop ~desc:"Target page ID") ]
          ~required:[ "page_id" ];
    };
    {
      name = "get_state";
      description = "Get the full state of a page (all widgets, focus, etc.)";
      input_schema =
        make_schema
          ~properties:[ ("page_id", string_prop ~desc:"Target page ID") ]
          ~required:[ "page_id" ];
    };
    {
      name = "execute_action";
      description = "Execute an action on a page";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ("action", object_prop ~desc:"Action definition JSON");
            ]
          ~required:[ "page_id"; "action" ];
    };
    {
      name = "validate_page";
      description = "Validate a page definition JSON without creating it";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_def", object_prop ~desc:"Page definition JSON to validate");
            ]
          ~required:[ "page_def" ];
    };
    {
      name = "get_catalog";
      description =
        "Get the widget/action/layout catalog (available types and parameters)";
      input_schema = make_schema ~properties:[] ~required:[];
    };
    {
      name = "resize";
      description = "Resize a page's viewport";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ("rows", int_prop ~desc:"New row count");
              ("cols", int_prop ~desc:"New column count");
            ]
          ~required:[ "page_id"; "rows"; "cols" ];
    };
    {
      name = "focus";
      description = "Set focus to a specific widget";
      input_schema =
        make_schema
          ~properties:
            [
              ("page_id", string_prop ~desc:"Target page ID");
              ("widget_id", string_prop ~desc:"Widget ID to focus");
            ]
          ~required:[ "page_id"; "widget_id" ];
    };
    {
      name = "get_focus";
      description = "Get current focus state of a page";
      input_schema =
        make_schema
          ~properties:[ ("page_id", string_prop ~desc:"Target page ID") ]
          ~required:[ "page_id" ];
    };
  ]

let tool_to_json t =
  `Assoc
    [
      ("name", `String t.name);
      ("description", `String t.description);
      ("inputSchema", t.input_schema);
    ]
