local Types = require("ui/types")

export type Key = "button" | "card" | "fill" | "icon" | "label" | "root" | "row" | "tooltip" | "track"

export type Node_button = Types.UINode & {
  parent: Types.UINode?,
}

export type Node_icon = Types.UINode & {
  parent: Types.UINode?,
}

export type Node_fill = Types.UINode & {
  parent: Types.UINode?,
}

export type Node_label = Types.UINode & {
  parent: Types.UINode?,
}

export type Node_track = Types.UINode & {
  parent: Types.UINode?,
  fill: Node_fill,
  label: Node_label,
}

export type Node_row = Types.UINode & {
  parent: Types.UINode?,
  track: Node_track,
}

export type Node_card = Types.UINode & {
  parent: Types.UINode?,
  button: Node_button,
  icon: Node_icon,
  row: Node_row,
}

export type Node_tooltip = Types.UINode & {
  parent: Types.UINode?,
}

export type Node_root = Types.UINode & {
  parent: Types.UINode?,
  card: Node_card,
  tooltip: Node_tooltip,
}

export type Root = Node_root

return {}
