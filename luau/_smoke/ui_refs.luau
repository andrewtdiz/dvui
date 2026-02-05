local UI = require("luau/ui_gen/app_ui")
local LoadUI = require("luau/ui/load_ui")
local Hydrate = require("ui/hydrate")

local function assert_ok(v, msg)
  if v then
    return
  end
  error(msg or "assert", 0)
end

local root: UI.Node_root = LoadUI.from_json("luau/ui_json/app.json")
local card = root.card

local root_children = root.children
assert_ok(type(root_children) == "table" and #root_children == 1, "root children")
assert_ok(root_children[1] == card, "card identity")

Hydrate(root)({})
assert_ok(root.children == root_children, "no-op preserves children")

local card_children = card.children
assert_ok(type(card_children) == "table" and #card_children == 3, "card children")

Hydrate(root){
  Hydrate(card){
    class = "x",
  },
}

assert_ok(root.children == root_children and #root_children == 1, "root children kept")
assert_ok(card.children == card_children and #card_children == 3, "card siblings kept")

local card_class = card.class
assert_ok(type(card_class) == "string" and string.find(card_class, "x", 1, true) ~= nil, "class patch")

Hydrate(card.button){
  children = { "X" },
}
assert_ok(type(card.button.children) == "table" and card.button.children[1] == "X", "children patch")

local replacement = { tag = "image", key = "icon", class = "z" }
Hydrate(card){ replacement }

assert_ok(card.icon == replacement, "named link replaced")
assert_ok(replacement.parent == card, "parent set on replacement")
