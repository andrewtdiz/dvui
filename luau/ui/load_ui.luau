local Types = require("ui/types")
local TailwindJson = require("luau/ui/tailwind_json")

type UINode = Types.UINode

local function is_tailwind_json_spec(spec: any): boolean
  if type(spec) ~= "table" then
    return false
  end
  if spec.layout ~= nil then
    return true
  end
  if spec.flex ~= nil then
    return true
  end
  if spec.pad ~= nil then
    return true
  end
  if spec.bg ~= nil then
    return true
  end
  if spec.border ~= nil then
    return true
  end
  if spec.rounded ~= nil then
    return true
  end
  if spec.opacity ~= nil then
    return true
  end
  if spec.z ~= nil then
    return true
  end
  if spec.text ~= nil then
    return true
  end
  if spec.hidden ~= nil then
    return true
  end
  if spec.clip ~= nil then
    return true
  end
  if spec.classExtra ~= nil then
    return true
  end
  return false
end

local function compute_key_path(key: string?, parent: UINode?): string?
  if type(key) ~= "string" or key == "" then
    return nil
  end
  if parent == nil then
    return key
  end
  local parent_path = parent.__keyPath
  if type(parent_path) == "string" and parent_path ~= "" then
    return parent_path .. "." .. key
  end
  local parent_key = parent.key
  if type(parent_key) == "string" and parent_key ~= "" then
    return parent_key .. "." .. key
  end
  return key
end

local function with_path_token(class_value: any, key_path: string): any
  local tok = "ui-path-" .. key_path
  if type(class_value) == "string" then
    if string.find(class_value, "__key=") ~= nil or string.find(class_value, "ui%-path%-") ~= nil then
      return class_value
    end
    if class_value == "" then
      return tok
    end
    return class_value .. " " .. tok
  end
  if class_value == nil then
    return tok
  end
  if type(class_value) == "function" then
    return function()
      return with_path_token(class_value(), key_path)
    end
  end
  return class_value
end

local function append_class_token(class_value: any, tok: string): any
  if type(class_value) == "string" then
    if class_value == "" then
      return tok
    end
    return class_value .. " " .. tok
  end
  if class_value == nil then
    return tok
  end
  if type(class_value) == "function" then
    return function()
      return append_class_token(class_value(), tok)
    end
  end
  return class_value
end

local function size_token_from_value(kind: "w" | "h", v: any): string?
  if v == nil then
    return nil
  end
  if type(v) == "number" then
    return kind .. "-[" .. tostring(v) .. "]"
  end
  if type(v) ~= "string" or v == "" then
    return nil
  end

  local prefix = kind .. "-"
  if string.sub(v, 1, #prefix) == prefix then
    return v
  end

  if v == "full" then
    return kind .. "-full"
  end
  if v == "screen" then
    return kind .. "-screen"
  end
  if v == "px" then
    return kind .. "-px"
  end
  if string.sub(v, -2) == "px" then
    local n = tonumber(string.sub(v, 1, -3))
    if n ~= nil then
      return kind .. "-[" .. tostring(n) .. "]"
    end
    return nil
  end
  if string.sub(v, -1) == "%" then
    local n = tonumber(string.sub(v, 1, -2))
    if n ~= nil and n == 100 then
      return kind .. "-full"
    end
    return nil
  end

  local n = tonumber(v)
  if n ~= nil then
    return kind .. "-[" .. tostring(n) .. "]"
  end
  return nil
end

local function with_size_tokens(class_value: any, width_value: any, height_value: any): any
  if type(class_value) == "function" or type(width_value) == "function" or type(height_value) == "function" then
    return function()
      local c = class_value
      if type(c) == "function" then
        c = c()
      end
      local w = width_value
      if type(w) == "function" then
        w = w()
      end
      local h = height_value
      if type(h) == "function" then
        h = h()
      end
      return with_size_tokens(c, w, h)
    end
  end

  local out = class_value
  local w_tok = size_token_from_value("w", width_value)
  if type(w_tok) == "string" then
    out = append_class_token(out, w_tok)
  end
  local h_tok = size_token_from_value("h", height_value)
  if type(h_tok) == "string" then
    out = append_class_token(out, h_tok)
  end
  return out
end

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

  if is_tailwind_json_spec(spec) then
    node.class = TailwindJson.toClass(spec)
  end

  local key_path = compute_key_path(key, parent)
  node.__keyPath = key_path
  if type(key_path) == "string" then
    node.class = with_path_token(node.class, key_path)
  end
  local has_layout_size = false
  if type(spec.layout) == "table" and type(spec.layout.size) == "table" then
    has_layout_size = true
  end
  if not has_layout_size then
    node.class = with_size_tokens(node.class, node.width, node.height)
  end

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

local function attach(parent: UINode, spec: any): any
  if type(parent) ~= "table" then
    error("ui attach parent must be node", 0)
  end
  if type(spec) ~= "table" then
    error("ui attach spec must be table", 0)
  end

  if spec.tag ~= nil then
    return build_node(spec, nil, parent)
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

  return build_node(root_value, root_key, parent)
end

local function from_json(module_id: string): any
  return from_spec(require(module_id))
end

return {
  from_spec = from_spec,
  attach = attach,
  from_json = from_json,
}
