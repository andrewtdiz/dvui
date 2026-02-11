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
local start_menu = root.StartMenu

local root_children = root.children
assert_ok(type(start_menu) == "table" and start_menu.tag == "div", "StartMenu node")
assert_ok(type(root_children) == "table" and #root_children == 2, "root children")
assert_ok(root_children[1] == card, "card identity")
assert_ok(root_children[2] == start_menu, "StartMenu identity")
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

assert_ok(root.children == root_children and #root_children == 2, "root children kept")
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
assert_ok(type(app_card.children) == "table" and #app_card.children == 4, "app card children kept")

local Toggle = require("luau/components/toggle")

do
  local called = 0
  local last = nil
  local function onChange(nextOn)
    called = called + 1
    last = nextOn
  end

  local on_node = Toggle({ on = true, onChange = onChange })
  local on_class = on_node.class
  local on_class_text = if type(on_class) == "function" then on_class() else on_class
  assert_ok(type(on_class_text) == "string" and string.find(on_class_text, "bg-blue-600", 1, true) ~= nil, "toggle on track class")
  assert_ok(type(on_node.onClick) == "function", "toggle onClick")
  on_node.onClick(nil, 0, "click")
  assert_ok(called == 1 and last == false, "toggle click inverts on")

  called = 0
  last = nil
  local off_node = Toggle({ on = false, onChange = onChange })
  local off_class = off_node.class
  local off_class_text = if type(off_class) == "function" then off_class() else off_class
  assert_ok(type(off_class_text) == "string" and string.find(off_class_text, "bg-neutral-900", 1, true) ~= nil, "toggle off track class")
  off_node.onClick(nil, 0, "click")
  assert_ok(called == 1 and last == true, "toggle click inverts off")
end
