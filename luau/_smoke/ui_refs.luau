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
assert_ok(card.parent == root, "parent link")

Hydrate(root)()
assert_ok(root.children == root_children, "no-op preserves children")

local card_children = card.children
assert_ok(type(card_children) == "table" and #card_children == 3, "card children")
assert_ok(type(card.icon) == "table" and card.icon.tag == "image", "icon node")
assert_ok(card.icon.src == "assets/sprite.png", "icon src")

Hydrate(card){
  class = "x",
}

assert_ok(root.children == root_children and #root_children == 1, "root children kept")
assert_ok(card.children == card_children and #card_children == 3, "card siblings kept")

local card_class = card.class
assert_ok(type(card_class) == "string" and string.find(card_class, "x", 1, true) ~= nil, "class patch")

Hydrate(card.button){
  children = { "X" },
}
assert_ok(type(card.button.children) == "table" and card.button.children[1] == "X", "children patch")

local App = require("luau/app")
local SolidLuau = require("solidluau")
local app_root = SolidLuau.createRoot(function(destroy)
  local node = App()
  destroy()
  return node
end)
local app_card = app_root.card
local app_icon = app_card.icon

assert_ok(type(app_icon) == "table" and app_icon.tag == "image", "app icon exists")
assert_ok(app_icon.src == "assets/sprite.png", "app icon src")
assert_ok(type(app_card.children) == "table" and #app_card.children == 3, "app card children kept")
