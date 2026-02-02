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

local function For(spec)
  return {
    __kind = "For",
    each = spec.each,
    key = spec.key,
    children = spec.children,
  }
end

local function Show(spec)
  return {
    __kind = "Show",
    when = spec.when,
    children = spec.children,
    fallback = spec.fallback,
  }
end

return {
  Create = Create,
  Tag = Tag,
  For = For,
  Show = Show,
}
