local module_cache = {}

function require(path)
  if type(path) ~= "string" then
    error("require path must be string", 0)
  end

  local key = path
  if string.sub(key, -5) ~= ".luau" then
    key = key .. ".luau"
  end

  local cached = module_cache[key]
  if cached ~= nil then
    return cached
  end

  local result, err = dvui_dofile(key)
  if err ~= nil then
    error(err, 0)
  end
  if result == nil then
    result = true
  end
  module_cache[key] = result
  return result
end

local app = require("luau/app")
local renderer = require("luau/ui_features_decl/renderer")
local animation = require("luau/ui_features_decl/animation")

function init()
  renderer.init(app)
end

function update(dt, input)
  animation.step(dt)
end

function on_event(kind, id, payload)
  renderer.dispatch_event(kind, id, payload)
end
