local function newMockUi()
  local nodes = {}
  local log = {}
  local listened_by_id = {}

  local EventKind = {
    click = 1,
    mouseenter = 2,
    mouseleave = 3,
    pointerdown = 4,
    pointerup = 5,
    input = 6,
    focus = 7,
    blur = 8,
    enter = 9,
  }

  local PropKey = {
    Text = 1,
    Class = 2,
    Transform = 3,
    Visual = 4,
    Scroll = 5,
    Anchor = 6,
    Image = 7,
    Src = 8,
  }

  local function require_node(id)
    local node = nodes[id]
    if node == nil then
      error("unknown node id " .. tostring(id), 0)
    end
    return node
  end

  local function find_child_pos(children, id)
    for i = 1, #children do
      if children[i] == id then
        return i
      end
    end
    return nil
  end

  local function insert_child_index0(parent, id, before_id)
    local children = parent.children
    local pos1 = #children + 1
    if before_id ~= nil then
      local before_pos = find_child_pos(children, before_id)
      if before_pos == nil then
        error("beforeId not a child", 0)
      end
      pos1 = before_pos
    end
    table.insert(children, pos1, id)
    return pos1 - 1
  end

  local function remove_child_index0(parent, id)
    local children = parent.children
    local pos = find_child_pos(children, id)
    if pos == nil then
      return nil
    end
    table.remove(children, pos)
    return pos - 1
  end

  local function append_log(entry)
    log[#log + 1] = entry
  end

  local function reset()
    table.clear(nodes)
    table.clear(listened_by_id)
    table.clear(log)
    nodes[0] = {
      id = 0,
      tag = "root",
      parent = nil,
      children = {},
      props = {},
    }
  end

  local function create(tag, id, parent_id, before_id)
    if nodes[id] ~= nil then
      error("create duplicate id " .. tostring(id), 0)
    end
    local parent = require_node(parent_id)
    nodes[id] = {
      id = id,
      tag = tag,
      parent = parent_id,
      children = {},
      props = {},
    }
    local index = insert_child_index0(parent, id, before_id)
    append_log({ op = "CREATE", tag = tag, id = id, parent = parent_id, index = index })
  end

  local function detach(id)
    local node = require_node(id)
    local from_parent_id = node.parent
    if from_parent_id == nil then
      return nil, nil
    end
    local parent = require_node(from_parent_id)
    local from_index = remove_child_index0(parent, id)
    node.parent = nil
    return from_parent_id, from_index
  end

  local function insert(id, parent_id, before_id)
    local from_parent_id, from_index = detach(id)
    local parent = require_node(parent_id)
    local node = require_node(id)
    node.parent = parent_id
    local index = insert_child_index0(parent, id, before_id)
    append_log({
      op = "MOVE",
      id = id,
      from_parent = from_parent_id,
      from_index = from_index,
      parent = parent_id,
      index = index,
    })
  end

  local function destroy_recursive(id)
    local node = require_node(id)
    while #node.children > 0 do
      destroy_recursive(node.children[#node.children])
    end

    local parent_id = node.parent
    if parent_id ~= nil then
      local parent = require_node(parent_id)
      remove_child_index0(parent, id)
    end

    nodes[id] = nil
    listened_by_id[id] = nil
    append_log({ op = "DESTROY", id = id })
  end

  local function remove(id)
    if id == 0 then
      error("remove root", 0)
    end
    destroy_recursive(id)
  end

  local function normalize_string(v)
    if v == nil then
      return ""
    end
    if type(v) == "string" then
      return v
    end
    return tostring(v)
  end

  local function apply_prop(node, key, value, out_props)
    if key == PropKey.Text then
      local v = normalize_string(value)
      node.props.Text = v
      out_props.Text = v
      return
    end
    if key == PropKey.Class then
      local v = normalize_string(value)
      node.props.Class = v
      out_props.Class = v
      return
    end
    if key == PropKey.Src then
      local v = normalize_string(value)
      node.props.Src = v
      out_props.Src = v
      return
    end
    if key == PropKey.Transform then
      node.props.Transform = value
      out_props.Transform = value
      return
    end
    if key == PropKey.Visual then
      node.props.Visual = value
      out_props.Visual = value
      return
    end
    if key == PropKey.Scroll then
      node.props.Scroll = value
      out_props.Scroll = value
      return
    end
    if key == PropKey.Anchor then
      node.props.Anchor = value
      out_props.Anchor = value
      return
    end
    if key == PropKey.Image then
      node.props.Image = value
      out_props.Image = value
      return
    end
    error("unknown PropKey " .. tostring(key), 0)
  end

  local function patch(id, ...)
    local node = require_node(id)
    local args = table.pack(...)
    if args.n % 2 ~= 0 then
      error("patch invalid arg count", 0)
    end

    local out_props = {}
    for i = 1, args.n, 2 do
      apply_prop(node, args[i], args[i + 1], out_props)
    end

    if next(out_props) ~= nil then
      append_log({ op = "UPDATE", id = id, props = out_props })
    end
  end

  local function setText(id, text)
    patch(id, PropKey.Text, text)
  end

  local function setClass(id, class_name)
    patch(id, PropKey.Class, class_name)
  end

  local function setTransform(id, transform)
    patch(id, PropKey.Transform, transform)
  end

  local function setVisual(id, visual)
    patch(id, PropKey.Visual, visual)
  end

  local function setScroll(id, scroll)
    patch(id, PropKey.Scroll, scroll)
  end

  local function setAnchor(id, anchor)
    patch(id, PropKey.Anchor, anchor)
  end

  local function setImage(id, image)
    patch(id, PropKey.Image, image)
  end

  local function setSrc(id, src)
    patch(id, PropKey.Src, src)
  end

  local function listenKind(id, kind)
    require_node(id)
    local set = listened_by_id[id]
    if set == nil then
      set = {}
      listened_by_id[id] = set
    end
    set[kind] = true
  end

  local function clearLog()
    table.clear(log)
  end

  local function getLog()
    return log
  end

  local function getNode(id)
    return nodes[id]
  end

  local function exists(id)
    return nodes[id] ~= nil
  end

  local function format_string(v)
    if type(v) == "string" then
      return string.format("%q", v)
    end
    if v == nil then
      return "nil"
    end
    return tostring(v)
  end

  local function toStrings()
    local out = {}
    for i = 1, #log do
      local entry = log[i]
      local op = entry.op
      if op == "CREATE" then
        out[i] = string.format("CREATE %s id=%d parent=%d index=%d", entry.tag, entry.id, entry.parent, entry.index)
      elseif op == "MOVE" then
        local from_parent = if entry.from_parent == nil then "nil" else tostring(entry.from_parent)
        local from_index = if entry.from_index == nil then "nil" else tostring(entry.from_index)
        out[i] = string.format(
          "MOVE id=%d parent=%d index=%d from_parent=%s from_index=%s",
          entry.id,
          entry.parent,
          entry.index,
          from_parent,
          from_index
        )
      elseif op == "UPDATE" then
        local parts = { "UPDATE id=" .. tostring(entry.id) }
        local props = entry.props
        if props.Text ~= nil then
          parts[#parts + 1] = "Text=" .. format_string(props.Text)
        end
        if props.Class ~= nil then
          parts[#parts + 1] = "Class=" .. format_string(props.Class)
        end
        if props.Src ~= nil then
          parts[#parts + 1] = "Src=" .. format_string(props.Src)
        end
        if props.Transform ~= nil then
          parts[#parts + 1] = "Transform=" .. format_string(props.Transform)
        end
        if props.Visual ~= nil then
          parts[#parts + 1] = "Visual=" .. format_string(props.Visual)
        end
        if props.Scroll ~= nil then
          parts[#parts + 1] = "Scroll=" .. format_string(props.Scroll)
        end
        if props.Anchor ~= nil then
          parts[#parts + 1] = "Anchor=" .. format_string(props.Anchor)
        end
        if props.Image ~= nil then
          parts[#parts + 1] = "Image=" .. format_string(props.Image)
        end
        out[i] = table.concat(parts, " ")
      elseif op == "DESTROY" then
        out[i] = string.format("DESTROY id=%d", entry.id)
      else
        out[i] = tostring(op)
      end
    end
    return out
  end

  local function snapshotLite(id)
    local node = require_node(id)
    local children = {}
    for i = 1, #node.children do
      children[i] = snapshotLite(node.children[i])
    end

    local out = { tag = node.tag, children = children }
    local props = node.props
    if node.tag == "text" then
      out.text = props.Text or ""
    end
    if props.Class ~= nil and props.Class ~= "" then
      out.class = props.Class
    end
    if props.Src ~= nil and props.Src ~= "" then
      out.src = props.Src
    end
    return out
  end

  local function findTextIdsByValue(text)
    local out = {}
    for id, node in pairs(nodes) do
      if node.tag == "text" and node.props.Text == text then
        out[#out + 1] = id
      end
    end
    table.sort(out)
    return out
  end

  reset()

  return {
    create = create,
    remove = remove,
    insert = insert,
    setText = setText,
    setClass = setClass,
    setTransform = setTransform,
    setVisual = setVisual,
    setScroll = setScroll,
    setAnchor = setAnchor,
    setImage = setImage,
    setSrc = setSrc,
    listenKind = listenKind,
    reset = reset,
    patch = patch,
    EventKind = EventKind,
    PropKey = PropKey,
    getLog = getLog,
    clearLog = clearLog,
    exists = exists,
    getNode = getNode,
    snapshotLite = snapshotLite,
    toStrings = toStrings,
    findTextIdsByValue = findTextIdsByValue,
  }
end

return {
  newMockUi = newMockUi,
}
