local function is_dynamic(v)
  local t = type(v)
  if t == "function" then
    return true
  end
  if t ~= "table" then
    return false
  end
  for _, child in pairs(v) do
    if is_dynamic(child) then
      return true
    end
  end
  return false
end

local function push(out, v)
  if v == nil or v == false or v == true then
    return
  end

  local t = type(v)
  if t == "string" then
    if v ~= "" then
      out[#out + 1] = v
    end
    return
  end

  if t == "number" then
    out[#out + 1] = tostring(v)
    return
  end

  if t == "function" then
    push(out, v())
    return
  end

  if t ~= "table" then
    out[#out + 1] = tostring(v)
    return
  end

  for _, child in ipairs(v) do
    push(out, child)
  end

  for k, cond in pairs(v) do
    if type(k) ~= "string" then
      continue
    end
    if type(cond) == "function" then
      cond = cond()
    end
    if cond then
      if k ~= "" then
        out[#out + 1] = k
      end
    end
  end
end

local function join_classes(...)
  local out = {}
  for i = 1, select("#", ...) do
    push(out, select(i, ...))
  end
  return table.concat(out, " ")
end

local function join_classes_list(args)
  local out = {}
  for i = 1, #args do
    push(out, args[i])
  end
  return table.concat(out, " ")
end

local function copy_spec(spec, omit)
  local out = {}
  if spec == nil then
    return out
  end
  for k, v in pairs(spec) do
    if omit == nil or omit[k] ~= true then
      out[k] = v
    end
  end
  return out
end

local function cn_impl(...)
  local args = { ... }
  for i = 1, #args do
    if is_dynamic(args[i]) then
      return function()
        return join_classes_list(args)
      end
    end
  end
  return join_classes_list(args)
end

local cn = setmetatable({}, {
  __call = function(_, ...)
    return cn_impl(...)
  end,
})

local function omit_with_class(omit)
  local out = { class = true }
  if omit == nil then
    return out
  end
  for k, v in pairs(omit) do
    out[k] = v
  end
  return out
end

cn.props = function(spec, ...)
  local out = copy_spec(spec, { class = true })
  out.class = cn_impl(..., if spec then spec.class else nil)
  return out
end

cn.props_omit = function(spec, omit, ...)
  local out = copy_spec(spec, omit_with_class(omit))
  out.class = cn_impl(..., if spec then spec.class else nil)
  return out
end

return cn
