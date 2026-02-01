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
  For = For,
  Show = Show,
}
