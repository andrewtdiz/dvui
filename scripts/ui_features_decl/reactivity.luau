local current_computation = nil
local current_owner = nil
local current_scope = nil

local queue = {}
local queue_head = 1
local queue_tail = 0
local flushing = false
local batch_depth = 0

local function new_scope(parent)
  local scope = {
    parent = parent,
    owned = {},
    children = {},
    cleanups = {},
    destroyed = false,
  }
  if parent ~= nil then
    parent.children[#parent.children + 1] = scope
  end
  return scope
end

local function run_cleanups(list)
  for i = #list, 1, -1 do
    local cb = list[i]
    list[i] = nil
    cb()
  end
end

local function destroy_scope(scope)
  if scope == nil or scope.destroyed then
    return
  end

  scope.destroyed = true

  for _, child in ipairs(scope.children) do
    destroy_scope(child)
  end

  for _, comp in ipairs(scope.owned) do
    if comp.destroy ~= nil then
      comp.destroy()
    end
  end

  run_cleanups(scope.cleanups)

  table.clear(scope.children)
  table.clear(scope.owned)
  table.clear(scope.cleanups)
end

local function flush()
  if flushing or batch_depth ~= 0 then
    return
  end

  flushing = true
  while queue_head <= queue_tail do
    local comp = queue[queue_head]
    queue[queue_head] = nil
    queue_head = queue_head + 1

    if comp ~= nil then
      comp.scheduled = false
      if not comp.destroyed then
        if comp.kind == "derive" then
          comp.dirty = true
          for observer in pairs(comp.observers) do
            if not observer.destroyed and not observer.scheduled then
              observer.scheduled = true
              queue_tail = queue_tail + 1
              queue[queue_tail] = observer
            end
          end
        else
          comp.run()
        end
      end
    end
  end

  queue_head = 1
  queue_tail = 0
  flushing = false
end

local function schedule(comp)
  if comp == nil or comp.destroyed or comp.scheduled then
    return
  end
  comp.scheduled = true
  queue_tail = queue_tail + 1
  queue[queue_tail] = comp
  flush()
end

local function clear_dependencies(comp)
  for _, sig in ipairs(comp.deps) do
    sig.observers[comp] = nil
  end
  table.clear(comp.deps)
  table.clear(comp.deps_set)
end

local function add_dependency(comp, sig)
  if comp.deps_set[sig] then
    return
  end
  comp.deps_set[sig] = true
  comp.deps[#comp.deps + 1] = sig
  sig.observers[comp] = true
end

local function cleanup(fn)
  local scope = current_scope
  if scope == nil then
    error("cleanup outside scope", 0)
  end
  scope.cleanups[#scope.cleanups + 1] = fn
end

local function batch(fn)
  batch_depth = batch_depth + 1
  local ok, result = xpcall(fn, debug.traceback)
  batch_depth = batch_depth - 1
  if batch_depth == 0 then
    flush()
  end
  if not ok then
    error(result, 0)
  end
  return result
end

local function untrack(fn)
  local prev_comp = current_computation
  current_computation = nil
  local ok, packed = xpcall(function()
    return table.pack(fn())
  end, debug.traceback)
  current_computation = prev_comp
  if not ok then
    error(packed, 0)
  end
  return table.unpack(packed, 1, packed.n)
end

local function scoped(owner, fn)
  local prev_owner = current_owner
  local prev_scope = current_scope
  current_owner = owner
  current_scope = owner
  local ok, packed = xpcall(function()
    return table.pack(fn())
  end, debug.traceback)
  current_owner = prev_owner
  current_scope = prev_scope
  if not ok then
    error(packed, 0)
  end
  return table.unpack(packed, 1, packed.n)
end

local function effect(fn)
  local owner = current_owner
  if owner == nil then
    error("effect outside root", 0)
  end

  local comp = {
    kind = "effect",
    owner = owner,
    fn = fn,
    deps = {},
    deps_set = {},
    cleanups = {},
    destroyed = false,
    scheduled = false,
  }

  local function destroy()
    if comp.destroyed then
      return
    end
    comp.destroyed = true
    clear_dependencies(comp)
    run_cleanups(comp.cleanups)
  end

  comp.destroy = destroy
  comp.run = function()
    if comp.destroyed then
      return
    end
    clear_dependencies(comp)
    run_cleanups(comp.cleanups)

    local prev_comp = current_computation
    local prev_owner = current_owner
    local prev_scope = current_scope
    current_computation = comp
    current_scope = comp
    current_owner = comp.owner

    local ok, err = xpcall(comp.fn, debug.traceback)

    current_computation = prev_comp
    current_scope = prev_scope
    current_owner = prev_owner

    if not ok then
      destroy()
      error(err, 0)
    end
  end

  owner.owned[#owner.owned + 1] = comp
  comp.run()
  return destroy
end

local function derive(fn)
  local owner = current_owner
  if owner == nil then
    error("derive outside root", 0)
  end

  local node = {
    kind = "derive",
    owner = owner,
    fn = fn,
    observers = {},
    deps = {},
    deps_set = {},
    cleanups = {},
    destroyed = false,
    scheduled = false,
    dirty = true,
    has_value = false,
    value = nil,
  }

  local function destroy()
    if node.destroyed then
      return
    end
    node.destroyed = true
    clear_dependencies(node)
    run_cleanups(node.cleanups)
    table.clear(node.observers)
  end

  local function compute()
    clear_dependencies(node)
    run_cleanups(node.cleanups)

    local prev_comp = current_computation
    local prev_owner = current_owner
    local prev_scope = current_scope
    current_computation = node
    current_scope = node
    current_owner = node.owner

    local ok, value = xpcall(node.fn, debug.traceback)

    current_computation = prev_comp
    current_scope = prev_scope
    current_owner = prev_owner

    if not ok then
      destroy()
      error(value, 0)
    end

    node.value = value
    node.has_value = true
    node.dirty = false
  end

  local function read()
    if node.destroyed then
      return nil
    end
    if current_computation ~= nil then
      add_dependency(current_computation, node)
    end
    if node.dirty or not node.has_value then
      compute()
    end
    return node.value
  end

  node.destroy = destroy
  owner.owned[#owner.owned + 1] = node
  return read
end

local function source(initial)
  local sig = {
    kind = "source",
    value = initial,
    observers = {},
  }

  local function access(...)
    if select("#", ...) == 0 then
      if current_computation ~= nil then
        add_dependency(current_computation, sig)
      end
      return sig.value
    end

    local v = ...
    if sig.value == v and (type(v) ~= "table" or table.isfrozen(v)) then
      return v
    end
    sig.value = v
    for observer in pairs(sig.observers) do
      schedule(observer)
    end
    return v
  end

  return access
end

local function root(fn)
  local scope = new_scope(nil)
  local function destroy()
    destroy_scope(scope)
  end

  local prev_owner = current_owner
  local prev_scope = current_scope
  current_owner = scope
  current_scope = scope

  local ok, result = xpcall(fn, debug.traceback, destroy)

  current_owner = prev_owner
  current_scope = prev_scope

  if not ok then
    destroy()
    error(result, 0)
  end

  return destroy, result
end

return {
  batch = batch,
  cleanup = cleanup,
  derive = derive,
  destroy_scope = destroy_scope,
  effect = effect,
  get_owner = function()
    return current_owner
  end,
  new_scope = new_scope,
  root = root,
  scoped = scoped,
  set_owner = function(owner)
    current_owner = owner
  end,
  source = source,
  untrack = untrack,
}
