local Types = require("ui/types")

type UINode = Types.UINode

local function build_node(spec: any, forced_key: string?, parent: UINode?): UINode
  if type(spec) ~= "table" then
    error("ui spec node must be table", 0)
  end

  local tag = spec.tag
  if type(tag) ~= "string" then
    error("ui spec node missing tag", 0)
  end

  local key = forced_key
  if spec.key ~= nil then
    if type(spec.key) ~= "string" then
      error("ui spec key must be string", 0)
    end
    if key ~= nil and spec.key ~= key then
      error("ui spec key mismatch", 0)
    end
    key = spec.key
  end

  local node: UINode = {}
  for k, v in pairs(spec) do
    if k ~= "children" then
      node[k] = v
    end
  end

  node.tag = tag
  node.key = key
  node.parent = parent

  local children_spec = spec.children
  if type(children_spec) == "table" then
    local children = {}
    for _, child_spec in ipairs(children_spec) do
      local child: any = child_spec

      if type(child_spec) == "table" then
        if child_spec.__kind ~= nil then
          child = child_spec
        elseif child_spec.tag ~= nil then
          child = build_node(child_spec, nil, node)
          local child_key = child.key
          if type(child_key) == "string" then
            node[child_key] = child
          end
        else
          local wrapper_key, wrapper_value = next(child_spec)
          if wrapper_key == nil or wrapper_value == nil then
            error("ui spec child wrapper empty", 0)
          end
          if next(child_spec, wrapper_key) ~= nil then
            error("ui spec child wrapper must have one key", 0)
          end
          if type(wrapper_key) ~= "string" then
            error("ui spec child key must be string", 0)
          end
          child = build_node(wrapper_value, wrapper_key, node)
          node[wrapper_key] = child
        end
      end

      table.insert(children, child)
    end
    node.children = children
  end

  return node
end

local function from_spec(spec: any): any
  if type(spec) ~= "table" then
    error("ui spec root must be table", 0)
  end

  if spec.tag ~= nil then
    return build_node(spec, "root", nil)
  end

  local root_key, root_value = next(spec)
  if root_key == nil or root_value == nil then
    error("ui spec root wrapper empty", 0)
  end
  if next(spec, root_key) ~= nil then
    error("ui spec root wrapper must have one key", 0)
  end
  if type(root_key) ~= "string" then
    error("ui spec root key must be string", 0)
  end

  return build_node(root_value, root_key, nil)
end

local function from_json(module_id: string): any
  return from_spec(require(module_id))
end

return {
  from_spec = from_spec,
  from_json = from_json,
}
