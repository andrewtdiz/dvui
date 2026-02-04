local UI = require("luau/ui_gen/app_ui")
local Hydrate = require("ui/hydrate")

local function assert_ok(v, msg)
  if v then
    return
  end
  error(msg or "assert", 0)
end

local ui = UI.create()
assert_ok(ui.root.cta.parent == ui.root, "parent link")

Hydrate.by_ref(ui.root, { [ui.root.cta] = { class = "x" } })
local class_value = ui.root.cta.class
assert_ok(type(class_value) == "string" and string.find(class_value, "x", 1, true) ~= nil, "class patch")

local fake = { tag = "div", key = "fake" }
local ok = pcall(function()
  Hydrate.by_ref(ui.root, { [fake] = { class = "y" } })
end)
assert_ok(ok == false, "unknown ref should error")
