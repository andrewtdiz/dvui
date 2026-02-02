local reactivity = require("luau/ui_features_decl/reactivity")

local source = reactivity.source

local t = 0
local scale = source(1.0)

local function update(dt)
  if dt == nil then
    return
  end
  t = t + dt
  scale(1.0 + 0.2 * math.sin(3 * t))
end

return {
  scale = scale,
  update = update,
}
