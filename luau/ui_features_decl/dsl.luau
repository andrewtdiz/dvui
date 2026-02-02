local function Create(tag)
  return function(spec)
    local node = { tag = tag }
    if spec ~= nil then
      for k, v in pairs(spec) do
        node[k] = v
      end
    end
    return node
  end
end

local function tag_builder(tag)
  return function(props)
    return function(children)
      local node = { tag = tag }
      if props ~= nil then
        for k, v in pairs(props) do
          node[k] = v
        end
      end
      if children ~= nil then
        node.children = children
      end
      return node
    end
  end
end

local Tag = setmetatable({}, {
  __index = function(self, tag)
    local fn = tag_builder(tag)
    rawset(self, tag, fn)
    return fn
  end,
})

local function build_for(spec, children)
  return {
    __kind = "For",
    each = spec.each,
    key = spec.key,
    children = children or spec.children,
  }
end

local function build_show(spec, children)
  return {
    __kind = "Show",
    when = spec.when,
    children = children or spec.children,
    fallback = spec.fallback,
  }
end

local function For(spec)
  if spec == nil then
    spec = {}
  end
  if spec.children ~= nil then
    return build_for(spec)
  end
  return function(children)
    return build_for(spec, children)
  end
end

local function Show(spec)
  if spec == nil then
    spec = {}
  end
  if spec.children ~= nil then
    return build_show(spec)
  end
  return function(children)
    return build_show(spec, children)
  end
end

return {
  Create = Create,
  Tag = Tag,
  For = For,
  Show = Show,
}
