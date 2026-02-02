local reactivity = require("luau/ui_features_decl/reactivity")

local createEffect = reactivity.createEffect
local createRoot = reactivity.createRoot
local createSignal = reactivity.createSignal
local new_scope = reactivity.new_scope
local destroy_scope = reactivity.destroy_scope
local get_owner = reactivity.get_owner
local set_owner = reactivity.set_owner
local untrack = reactivity.untrack
local runWithOwner = reactivity.runWithOwner
local run_mounts = reactivity.run_mounts

local next_id = 1
local listened_by_id = {}
local handlers_by_id = {}
local app_destroy = nil

local kind_name_by_value = {}
for name, value in pairs(ui.EventKind) do
  kind_name_by_value[value] = name
end

local function alloc_id()
  local id = next_id
  next_id = next_id + 1
  return id
end

local function listen_event(id, kind)
  local set = listened_by_id[id]
  if set == nil then
    set = {}
    listened_by_id[id] = set
  end
  if set[kind] then
    return
  end
  set[kind] = true
  ui.listen_kind(id, kind)
end

local function set_handler(id, kind, fn)
  local map = handlers_by_id[id]
  if map == nil then
    map = {}
    handlers_by_id[id] = map
  end
  map[kind] = fn
  listen_event(id, kind)
end

local function clear_id_bindings(id)
  handlers_by_id[id] = nil
  listened_by_id[id] = nil
end

local function normalize_text(v)
  if v == nil then
    return ""
  end
  if type(v) == "string" then
    return v
  end
  return tostring(v)
end

local function mount_class(id, class_value)
  if class_value == nil then
    return
  end

  if type(class_value) == "function" then
    local last = nil
    createEffect(function()
      local v = normalize_text(class_value())
      if v ~= last then
        last = v
        ui.set_class(id, v)
      end
    end)
    return
  end

  ui.set_class(id, normalize_text(class_value))
end

local function mount_value(id, setter, value)
  if value == nil then
    return
  end

  if type(value) == "function" then
    createEffect(function()
      setter(id, value())
    end)
    return
  end

  if type(value) == "table" then
    local has_fn = false
    for _, v in pairs(value) do
      if type(v) == "function" then
        has_fn = true
        break
      end
    end
    if has_fn then
      local out = {}
      createEffect(function()
        for k in pairs(out) do
          out[k] = nil
        end
        for k, v in pairs(value) do
          out[k] = if type(v) == "function" then v() else v
        end
        setter(id, out)
      end)
      return
    end
  end

  setter(id, value)
end

local function mount_transform(id, transform_value, scale_value)
  if transform_value == nil then
    if scale_value == nil then
      return
    end
    mount_value(id, ui.set_transform, { scale = scale_value })
    return
  end

  if scale_value == nil then
    mount_value(id, ui.set_transform, transform_value)
    return
  end

  local out = {}
  createEffect(function()
    for k in pairs(out) do
      out[k] = nil
    end

    local base = transform_value
    if type(base) == "function" then
      base = base()
    end
    if base ~= nil and type(base) ~= "table" then
      error("transform must be table", 0)
    end

    if base ~= nil then
      for k, v in pairs(base) do
        out[k] = if type(v) == "function" then v() else v
      end
    end

    local scale = scale_value
    if type(scale) == "function" then
      scale = scale()
    end
    out.scale = scale
    ui.set_transform(id, out)
  end)
end

local function mount_props(id, props, scale_value)
  if props == nil then
    mount_transform(id, nil, scale_value)
    return
  end

  mount_value(id, ui.set_visual, props.visual)
  mount_transform(id, props.transform, scale_value)
  mount_value(id, ui.set_scroll, props.scroll)
  mount_value(id, ui.set_anchor, props.anchor)
  mount_value(id, ui.set_image, props.image)

  local src = props.src
  if src ~= nil then
    if type(src) == "function" then
      createEffect(function()
        ui.set_src(id, normalize_text(src()))
      end)
    else
      ui.set_src(id, normalize_text(src))
    end
  end

  local listen = props.listen
  if listen ~= nil then
    if type(listen) == "function" then
      createEffect(function()
        local list = listen()
        if type(list) ~= "table" then
          return
        end
        for _, event_name in ipairs(list) do
          local kind = ui.EventKind[event_name]
          if kind == nil then
            error(string.format("unknown event: %s", tostring(event_name)), 0)
          end
          listen_event(id, kind)
        end
      end)
    else
      if type(listen) ~= "table" then
        return
      end
      for _, event_name in ipairs(listen) do
        local kind = ui.EventKind[event_name]
        if kind == nil then
          error(string.format("unknown event: %s", tostring(event_name)), 0)
        end
        listen_event(id, kind)
      end
    end
  end
end

local event_key_to_kind = {
  onClick = ui.EventKind.click,
  onMouseEnter = ui.EventKind.mouseenter,
  onMouseLeave = ui.EventKind.mouseleave,
  onInput = ui.EventKind.input,
  onFocus = ui.EventKind.focus,
  onBlur = ui.EventKind.blur,
  onEnter = ui.EventKind.enter,
}

local function apply_event_handlers(node, id)
  for k, v in pairs(node) do
    local kind = event_key_to_kind[k]
    if kind ~= nil and type(v) == "function" then
      set_handler(id, kind, v)
    end
  end
end

local destroy_record = nil

local function mount_any(node, parent_id, before_id, forced_scope)
  local node_type = type(node)
  if node_type == "string" or node_type == "number" or node_type == "boolean" then
    local prev_owner = get_owner()
    local scope = forced_scope or new_scope(prev_owner)
    set_owner(scope)

    local id = alloc_id()
    ui.create("text", id, parent_id, before_id)
    ui.set_text(id, normalize_text(node))

    run_mounts(scope)
    set_owner(prev_owner)

    return {
      kind = "text",
      id = id,
      scope = scope,
    }
  end

  if node_type == "function" then
    local prev_owner = get_owner()
    local scope = forced_scope or new_scope(prev_owner)
    set_owner(scope)

    local id = alloc_id()
    ui.create("text", id, parent_id, before_id)
    local last = nil
    createEffect(function()
      local v = normalize_text(node())
      if v ~= last then
        last = v
        ui.set_text(id, v)
      end
    end)

    run_mounts(scope)
    set_owner(prev_owner)

    return {
      kind = "text",
      id = id,
      scope = scope,
    }
  end

  if node_type ~= "table" then
    return nil
  end

  local kind = node.__kind
  if kind == "For" then
    local prev_owner = get_owner()
    local scope = forced_scope or new_scope(prev_owner)
    set_owner(scope)

    local slot_id = alloc_id()
    ui.create("slot", slot_id, parent_id, before_id)
    ui.set_class(slot_id, "hidden")

    local each_fn = node.each
    if type(each_fn) ~= "function" then
      local fixed = if type(each_fn) == "table" then each_fn else {}
      each_fn = function()
        return fixed
      end
    end
    local key_fn = node.key
    if type(key_fn) ~= "function" then
      key_fn = function(item, i)
        return item
      end
    end
    local child_fn = node.children
    if type(child_fn) ~= "function" then
      error("For.children must be function", 0)
    end

    local record = {
      kind = "for",
      slot_id = slot_id,
      parent_id = parent_id,
      scope = scope,
      each_fn = each_fn,
      key_fn = key_fn,
      child_fn = child_fn,
      by_key = {},
      value_by_key = {},
      value_set_by_key = {},
      index_by_key = {},
      index_set_by_key = {},
      order = {},
    }

    local function update()
      local items = each_fn()
      if type(items) ~= "table" then
        items = {}
      end

      local seen = {}
      local next_order = {}

      for i, item in ipairs(items) do
        local key = key_fn(item, i)
        if key == nil then
          key = i
        end
        if seen[key] then
          error("duplicate For key", 0)
        end
        seen[key] = true
        next_order[#next_order + 1] = key

        local mounted = record.by_key[key]
        if mounted == nil then
          local value, set_value = createSignal(item)
          local index, set_index = createSignal(i)
          record.value_by_key[key] = value
          record.value_set_by_key[key] = set_value
          record.index_by_key[key] = index
          record.index_set_by_key[key] = set_index

          local parent_owner = get_owner()
          local child_scope = new_scope(parent_owner)
          local child_node = runWithOwner(child_scope, function()
            return untrack(function()
              return child_fn(item, i, value, index, key, set_value, set_index)
            end)
          end)
          mounted = mount_any(child_node, parent_id, slot_id, child_scope)
          if mounted == nil or mounted.id == nil then
            destroy_scope(child_scope)
            error("For child must mount to a node id", 0)
          end
          record.by_key[key] = mounted
        else
          local set_value = record.value_set_by_key[key]
          if set_value ~= nil then
            set_value(item)
          end
          local set_index = record.index_set_by_key[key]
          if set_index ~= nil then
            set_index(i)
          end
        end
      end

      local remove_keys = {}
      for key in pairs(record.by_key) do
        if not seen[key] then
          remove_keys[#remove_keys + 1] = key
        end
      end
      for _, key in ipairs(remove_keys) do
        destroy_record(record.by_key[key])
        record.by_key[key] = nil
        record.value_by_key[key] = nil
        record.value_set_by_key[key] = nil
        record.index_by_key[key] = nil
        record.index_set_by_key[key] = nil
      end

      local prev_order = record.order
      local prev_set = {}
      for i = 1, #prev_order do
        prev_set[prev_order[i]] = true
      end

      local order_ok = true
      local prev_index = 1
      local new_tail = false
      for i = 1, #next_order do
        local key = next_order[i]
        if prev_set[key] then
          if new_tail then
            order_ok = false
            break
          end
          while prev_index <= #prev_order and not seen[prev_order[prev_index]] do
            prev_index += 1
          end
          if prev_index > #prev_order or prev_order[prev_index] ~= key then
            order_ok = false
            break
          end
          prev_index += 1
        else
          new_tail = true
        end
      end

      if not order_ok then
        local before = slot_id
        for i = #next_order, 1, -1 do
          local key = next_order[i]
          local child_record = record.by_key[key]
          if child_record ~= nil then
            ui.insert(child_record.id, parent_id, before)
            before = child_record.id
          end
        end
      end

      record.order = next_order
    end

    createEffect(update)

    run_mounts(scope)
    set_owner(prev_owner)

    return record
  end

  if kind == "Show" then
    local prev_owner = get_owner()
    local scope = forced_scope or new_scope(prev_owner)
    set_owner(scope)

    local slot_id = alloc_id()
    ui.create("slot", slot_id, parent_id, before_id)
    ui.set_class(slot_id, "hidden")

    local when_fn = node.when
    if type(when_fn) ~= "function" then
      local fixed = when_fn
      when_fn = function()
        return fixed
      end
    end
    local child_value = node.children
    local fallback_value = node.fallback

    local record = {
      kind = "show",
      slot_id = slot_id,
      parent_id = parent_id,
      scope = scope,
      when_fn = when_fn,
      child_value = child_value,
      fallback_value = fallback_value,
      current = nil,
      showing = nil,
    }

    local function mount_branch(value)
      local parent_owner = get_owner()
      local branch_scope = new_scope(parent_owner)

      local v = runWithOwner(branch_scope, function()
        return untrack(function()
          local out = value
          if type(out) == "function" then
            out = out()
          end
          return out
        end)
      end)

      local mounted = mount_any(v, parent_id, slot_id, branch_scope)
      if mounted == nil then
        destroy_scope(branch_scope)
      end
      return mounted
    end

    local function update()
      local should_show = not not when_fn()
      if should_show == record.showing then
        return
      end

      if record.current ~= nil then
        destroy_record(record.current)
        record.current = nil
      end

      record.showing = should_show
      if should_show then
        record.current = mount_branch(child_value)
      elseif fallback_value ~= nil then
        record.current = mount_branch(fallback_value)
      end
    end

    createEffect(update)

    run_mounts(scope)
    set_owner(prev_owner)

    return record
  end

  local tag = node.tag
  if tag == nil then
    local records = {}
    local prev_owner = nil
    if forced_scope ~= nil then
      prev_owner = get_owner()
      set_owner(forced_scope)
    end
    for _, child in ipairs(node) do
      local child_record = mount_any(child, parent_id, before_id)
      if child_record ~= nil then
        records[#records + 1] = child_record
      end
    end
    if forced_scope ~= nil then
      run_mounts(forced_scope)
      set_owner(prev_owner)
      return {
        kind = "fragment",
        scope = forced_scope,
        children = records,
      }
    end
    return {
      kind = "fragment",
      children = records,
    }
  end

  local prev_owner = get_owner()
  local scope = forced_scope or new_scope(prev_owner)
  set_owner(scope)

  local id = alloc_id()
  ui.create(tag, id, parent_id, before_id)

  apply_event_handlers(node, id)

  mount_class(id, node.class)

  mount_props(id, node.props, node.scale)

  local children_records = {}
  local children_value = node.children
  if children_value ~= nil then
    if type(children_value) == "table" and children_value.tag == nil and children_value.__kind == nil then
      for _, child in ipairs(children_value) do
        local child_record = mount_any(child, id, nil)
        if child_record ~= nil then
          children_records[#children_records + 1] = child_record
        end
      end
    else
      local child_record = mount_any(children_value, id, nil)
      if child_record ~= nil then
        children_records[#children_records + 1] = child_record
      end
    end
  end

  set_owner(prev_owner)

  run_mounts(scope)
  return {
    kind = "node",
    id = id,
    scope = scope,
    children = children_records,
  }
end

local function clear_bindings_record(record)
  if record == nil then
    return
  end

  local kind = record.kind
  if kind == "node" or kind == "text" then
    clear_id_bindings(record.id)
    if record.children ~= nil then
      for _, child in ipairs(record.children) do
        clear_bindings_record(child)
      end
    end
    return
  end

  if kind == "fragment" then
    for _, child in ipairs(record.children) do
      clear_bindings_record(child)
    end
    return
  end

  if kind == "for" then
    clear_id_bindings(record.slot_id)
    for _, child in pairs(record.by_key) do
      clear_bindings_record(child)
    end
    return
  end

  if kind == "show" then
    clear_id_bindings(record.slot_id)
    clear_bindings_record(record.current)
  end
end

destroy_record = function(record)
  if record == nil then
    return
  end

  local kind = record.kind
  if kind == "node" or kind == "text" then
    destroy_scope(record.scope)
    clear_bindings_record(record)
    ui.remove(record.id)
    return
  end

  if kind == "fragment" then
    if record.scope ~= nil then
      destroy_scope(record.scope)
    end
    for _, child in ipairs(record.children) do
      destroy_record(child)
    end
    return
  end

  if kind == "for" then
    destroy_scope(record.scope)
    clear_bindings_record(record)
    for _, child in pairs(record.by_key) do
      ui.remove(child.id)
    end
    ui.remove(record.slot_id)
    return
  end

  if kind == "show" then
    destroy_scope(record.scope)
    clear_bindings_record(record)
    destroy_record(record.current)
    ui.remove(record.slot_id)
  end
end

local function mount_root(component)
  local tree = nil
  local destroy_reactive = nil

  createRoot(function(dispose)
    destroy_reactive = dispose
    tree = mount_any(component(), 0, nil)
    return tree
  end)

  return function()
    if tree ~= nil then
      destroy_record(tree)
      tree = nil
    end
    if destroy_reactive ~= nil then
      destroy_reactive()
      destroy_reactive = nil
    end
  end
end

local function dispatch_event(kind, id, payload)
  local map = handlers_by_id[id]
  if map == nil then
    return
  end
  local handler = map[kind]
  if handler == nil then
    return
  end
  local kind_name = kind_name_by_value[kind]
  handler(payload, id, kind_name)
end

local function init(component)
  if app_destroy ~= nil then
    app_destroy()
    app_destroy = nil
  end

  ui.reset()

  next_id = 1
  table.clear(listened_by_id)
  table.clear(handlers_by_id)
  app_destroy = mount_root(component)
end

return {
  init = init,
  dispatch_event = dispatch_event,
}
