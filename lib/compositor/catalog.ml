(** Widget catalog: static metadata about available widgets, actions, layouts.
*)

type param_type =
  | String
  | Bool
  | Int
  | Float
  | String_list
  | Enum of string list

type param = {
  name : string;
  typ : param_type;
  required : bool;
  default : Yojson.Safe.t option;
}

type widget_entry = {
  name : string;
  category : string;
  params : param list;
  events : string list;
  queryable : (string * param_type) list;
  focusable : bool;
}

let type_to_json = function
  | String -> `String "string"
  | Bool -> `String "bool"
  | Int -> `String "int"
  | Float -> `String "float"
  | String_list -> `String "string[]"
  | Enum values -> `String (String.concat "|" values)

let param_to_json (p : param) =
  let fields =
    [
      ("name", `String p.name);
      ("type", type_to_json p.typ);
      ("required", `Bool p.required);
    ]
    @ match p.default with Some d -> [ ("default", d) ] | None -> []
  in
  `Assoc fields

let entry_to_json e =
  `Assoc
    [
      ("name", `String e.name);
      ("category", `String e.category);
      ("params", `List (List.map param_to_json e.params));
      ("events", `List (List.map (fun s -> `String s) e.events));
      ( "queryable",
        `List
          (List.map
             (fun (n, t) ->
               `Assoc [ ("name", `String n); ("type", type_to_json t) ])
             e.queryable) );
      ("focusable", `Bool e.focusable);
    ]

let widget_catalog () =
  [
    {
      name = "button";
      category = "input";
      params =
        [
          { name = "label"; typ = String; required = true; default = None };
          {
            name = "disabled";
            typ = Bool;
            required = false;
            default = Some (`Bool false);
          };
        ];
      events = [ "click" ];
      queryable = [ ("label", String) ];
      focusable = true;
    };
    {
      name = "checkbox";
      category = "input";
      params =
        [
          {
            name = "label";
            typ = String;
            required = false;
            default = Some (`String "");
          };
          {
            name = "checked";
            typ = Bool;
            required = false;
            default = Some (`Bool false);
          };
          {
            name = "disabled";
            typ = Bool;
            required = false;
            default = Some (`Bool false);
          };
        ];
      events = [ "toggle" ];
      queryable = [ ("label", String); ("checked", Bool) ];
      focusable = true;
    };
    {
      name = "textbox";
      category = "input";
      params =
        [
          {
            name = "title";
            typ = String;
            required = false;
            default = Some (`String "");
          };
          {
            name = "width";
            typ = Int;
            required = false;
            default = Some (`Int 30);
          };
          {
            name = "initial";
            typ = String;
            required = false;
            default = Some (`String "");
          };
          {
            name = "placeholder";
            typ = String;
            required = false;
            default = None;
          };
          {
            name = "mask";
            typ = Bool;
            required = false;
            default = Some (`Bool false);
          };
        ];
      events = [ "change" ];
      queryable = [ ("text", String); ("cursor", Int) ];
      focusable = true;
    };
    {
      name = "textarea";
      category = "input";
      params =
        [
          {
            name = "title";
            typ = String;
            required = false;
            default = Some (`String "");
          };
          {
            name = "width";
            typ = Int;
            required = false;
            default = Some (`Int 40);
          };
          {
            name = "height";
            typ = Int;
            required = false;
            default = Some (`Int 5);
          };
          {
            name = "initial";
            typ = String;
            required = false;
            default = Some (`String "");
          };
          {
            name = "placeholder";
            typ = String;
            required = false;
            default = None;
          };
        ];
      events = [ "change" ];
      queryable = [ ("text", String) ];
      focusable = true;
    };
    {
      name = "select";
      category = "input";
      params =
        [
          { name = "title"; typ = String; required = true; default = None };
          { name = "items"; typ = String_list; required = true; default = None };
          {
            name = "max_visible";
            typ = Int;
            required = false;
            default = Some (`Int 10);
          };
        ];
      events = [ "select" ];
      queryable = [ ("selection", String) ];
      focusable = true;
    };
    {
      name = "radio";
      category = "input";
      params =
        [
          {
            name = "label";
            typ = String;
            required = false;
            default = Some (`String "");
          };
          {
            name = "selected";
            typ = Bool;
            required = false;
            default = Some (`Bool false);
          };
          {
            name = "disabled";
            typ = Bool;
            required = false;
            default = Some (`Bool false);
          };
        ];
      events = [ "select" ];
      queryable = [ ("label", String); ("selected", Bool) ];
      focusable = true;
    };
    {
      name = "switch";
      category = "input";
      params =
        [
          {
            name = "label";
            typ = String;
            required = false;
            default = Some (`String "");
          };
          {
            name = "on";
            typ = Bool;
            required = false;
            default = Some (`Bool false);
          };
          {
            name = "disabled";
            typ = Bool;
            required = false;
            default = Some (`Bool false);
          };
        ];
      events = [ "toggle" ];
      queryable = [ ("label", String); ("on", Bool) ];
      focusable = true;
    };
    {
      name = "pager";
      category = "display";
      params =
        [
          {
            name = "title";
            typ = String;
            required = false;
            default = Some (`String "");
          };
          { name = "text"; typ = String; required = true; default = None };
        ];
      events = [];
      queryable = [ ("offset", Int); ("line_count", Int) ];
      focusable = true;
    };
    {
      name = "list";
      category = "display";
      params =
        [
          { name = "items"; typ = String_list; required = true; default = None };
          {
            name = "indent";
            typ = Int;
            required = false;
            default = Some (`Int 2);
          };
          {
            name = "expand_all";
            typ = Bool;
            required = false;
            default = Some (`Bool false);
          };
        ];
      events = [ "select" ];
      queryable = [ ("selected", String); ("cursor", Int) ];
      focusable = true;
    };
    {
      name = "description_list";
      category = "display";
      params =
        [
          {
            name = "title";
            typ = String;
            required = false;
            default = Some (`String "");
          };
          { name = "items"; typ = String_list; required = true; default = None };
        ];
      events = [];
      queryable = [];
      focusable = false;
    };
  ]

type action_entry = { action_name : string; action_params : param list }
(** Action catalog *)

let action_to_json e =
  `Assoc
    [
      ("name", `String e.action_name);
      ("params", `List (List.map param_to_json e.action_params));
    ]

let action_catalog () =
  [
    {
      action_name = "set_text";
      action_params =
        [
          { name = "target"; typ = String; required = true; default = None };
          { name = "value"; typ = String; required = true; default = None };
        ];
    };
    {
      action_name = "set_checked";
      action_params =
        [
          { name = "target"; typ = String; required = true; default = None };
          { name = "value"; typ = Bool; required = true; default = None };
        ];
    };
    {
      action_name = "toggle";
      action_params =
        [ { name = "target"; typ = String; required = true; default = None } ];
    };
    {
      action_name = "append_text";
      action_params =
        [
          { name = "target"; typ = String; required = true; default = None };
          { name = "value"; typ = String; required = true; default = None };
        ];
    };
    {
      action_name = "push_modal";
      action_params =
        [
          { name = "modal_def"; typ = String; required = true; default = None };
        ];
    };
    {
      action_name = "close_modal";
      action_params =
        [
          {
            name = "outcome";
            typ = Enum [ "commit"; "cancel" ];
            required = true;
            default = None;
          };
        ];
    };
    {
      action_name = "navigate";
      action_params =
        [ { name = "target"; typ = String; required = true; default = None } ];
    };
    { action_name = "back"; action_params = [] };
    { action_name = "quit"; action_params = [] };
    {
      action_name = "focus";
      action_params =
        [ { name = "target"; typ = String; required = true; default = None } ];
    };
    {
      action_name = "emit";
      action_params =
        [ { name = "event"; typ = String; required = true; default = None } ];
    };
    {
      action_name = "set_disabled";
      action_params =
        [
          { name = "target"; typ = String; required = true; default = None };
          { name = "value"; typ = Bool; required = true; default = None };
        ];
    };
    {
      action_name = "set_visible";
      action_params =
        [
          { name = "target"; typ = String; required = true; default = None };
          { name = "value"; typ = Bool; required = true; default = None };
        ];
    };
    {
      action_name = "set_items";
      action_params =
        [
          { name = "target"; typ = String; required = true; default = None };
          { name = "items"; typ = String_list; required = true; default = None };
        ];
    };
  ]

type layout_entry = { layout_name : string; layout_params : param list }
(** Layout catalog *)

let layout_to_json e =
  `Assoc
    [
      ("name", `String e.layout_name);
      ("params", `List (List.map param_to_json e.layout_params));
    ]

let layout_catalog () =
  [
    {
      layout_name = "flex";
      layout_params =
        [
          {
            name = "direction";
            typ = Enum [ "row"; "column" ];
            required = false;
            default = Some (`String "column");
          };
          { name = "gap"; typ = Int; required = false; default = Some (`Int 0) };
          { name = "padding"; typ = String; required = false; default = None };
          {
            name = "justify";
            typ =
              Enum [ "start"; "center"; "end"; "space_between"; "space_around" ];
            required = false;
            default = Some (`String "start");
          };
          {
            name = "align_items";
            typ = Enum [ "start"; "center"; "end"; "stretch" ];
            required = false;
            default = Some (`String "stretch");
          };
        ];
    };
    {
      layout_name = "grid";
      layout_params =
        [
          { name = "rows"; typ = String_list; required = true; default = None };
          { name = "cols"; typ = String_list; required = true; default = None };
          {
            name = "row_gap";
            typ = Int;
            required = false;
            default = Some (`Int 0);
          };
          {
            name = "col_gap";
            typ = Int;
            required = false;
            default = Some (`Int 0);
          };
        ];
    };
    {
      layout_name = "box";
      layout_params =
        [
          { name = "title"; typ = String; required = false; default = None };
          {
            name = "style";
            typ =
              Enum [ "none"; "single"; "double"; "rounded"; "ascii"; "heavy" ];
            required = false;
            default = Some (`String "single");
          };
          { name = "padding"; typ = String; required = false; default = None };
        ];
    };
    {
      layout_name = "card";
      layout_params =
        [
          { name = "title"; typ = String; required = false; default = None };
          { name = "footer"; typ = String; required = false; default = None };
          { name = "accent"; typ = Int; required = false; default = None };
        ];
    };
  ]
