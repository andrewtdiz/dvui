local function is_int(n: number): boolean
  return n == math.floor(n)
end

local function format_number(n: number): string
  if n ~= n or n == math.huge or n == -math.huge then
    return "0"
  end
  if is_int(n) then
    return tostring(n)
  end
  local s = string.format("%.6f", n)
  s = string.gsub(s, "0+$", "")
  s = string.gsub(s, "%.$", "")
  if s == "-0" then
    return "0"
  end
  return s
end

local function push_token(out: { string }, tok: string?)
  if type(tok) ~= "string" or tok == "" then
    return
  end
  table.insert(out, tok)
end

local function is_color_token(s: any): boolean
  if type(s) ~= "string" or s == "" then
    return false
  end
  if s == "black" or s == "white" or s == "transparent" then
    return true
  end
  if string.find(s, "-", 1, true) ~= nil then
    return true
  end
  if s == "content" or s == "window" or s == "control" or s == "highlight" or s == "err" then
    return true
  end
  if s == "app1" or s == "app2" or s == "app3" then
    return true
  end
  return false
end

local function layout_to_tokens(node: any, out: { string })
  local layout = node.layout
  if type(layout) ~= "table" then
    return
  end

  if layout.abs == true then
    push_token(out, "absolute")
  end

  local anchor = layout.anchor
  if type(anchor) == "string" then
    local tok = ({
      ["top-left"] = "anchor-top-left",
      ["top"] = "anchor-top",
      ["top-right"] = "anchor-top-right",
      ["left"] = "anchor-left",
      ["center"] = "anchor-center",
      ["right"] = "anchor-right",
      ["bottom-left"] = "anchor-bottom-left",
      ["bottom"] = "anchor-bottom",
      ["bottom-right"] = "anchor-bottom-right",
    })[anchor]
    push_token(out, tok)
  end

  local inset = layout.inset
  if type(inset) == "table" then
    local function emit_inset(side: string, v: any)
      if type(v) == "number" then
        push_token(out, side .. "-[" .. format_number(v) .. "]")
        return
      end
      if type(v) == "table" and type(v.pct) == "number" then
        push_token(out, side .. "-[" .. format_number(v.pct * 100) .. "%]")
      end
    end

    emit_inset("left", inset.left)
    emit_inset("top", inset.top)
    emit_inset("right", inset.right)
    emit_inset("bottom", inset.bottom)
  end

  local size = layout.size
  if type(size) == "table" then
    local w = size.w
    if type(w) == "number" then
      push_token(out, "w-[" .. format_number(w) .. "]")
    elseif type(w) == "table" and type(w.tw) == "number" then
      push_token(out, "w-" .. format_number(w.tw))
    elseif w == "full" or w == "screen" then
      push_token(out, "w-full")
    end

    local h = size.h
    if type(h) == "number" then
      push_token(out, "h-[" .. format_number(h) .. "]")
    elseif type(h) == "table" and type(h.tw) == "number" then
      push_token(out, "h-" .. format_number(h.tw))
    elseif h == "full" or h == "screen" then
      push_token(out, "h-full")
    end
  end
end

local function scale_to_tokens(node: any, out: { string })
  local v = node.scale
  if type(v) ~= "number" then
    return
  end
  if v ~= v or v == math.huge or v == -math.huge or v <= 0 then
    return
  end

  local p = v * 100
  local rounded = math.floor(p + 0.5)
  if math.abs(p - rounded) < 1e-6 and rounded >= 10 then
    push_token(out, "scale-" .. tostring(rounded))
  else
    push_token(out, "scale-[" .. format_number(v) .. "]")
  end
end

local function flex_to_tokens(node: any, out: { string })
  local flex = node.flex
  if type(flex) ~= "table" then
    return
  end

  push_token(out, "flex")

  if flex.dir == "row" then
    push_token(out, "flex-row")
  elseif flex.dir == "col" then
    push_token(out, "flex-col")
  end

  if flex.items == "start" then
    push_token(out, "items-start")
  elseif flex.items == "center" then
    push_token(out, "items-center")
  elseif flex.items == "end" then
    push_token(out, "items-end")
  end

  if flex.justify == "start" then
    push_token(out, "justify-start")
  elseif flex.justify == "center" then
    push_token(out, "justify-center")
  elseif flex.justify == "end" then
    push_token(out, "justify-end")
  elseif flex.justify == "between" then
    push_token(out, "justify-between")
  elseif flex.justify == "around" then
    push_token(out, "justify-around")
  end

  local gap = flex.gap
  if type(gap) == "number" then
    push_token(out, "gap-" .. format_number(gap))
  elseif type(gap) == "table" then
    local x = gap.x
    local y = gap.y
    if type(x) == "number" and type(y) == "number" and x == y then
      push_token(out, "gap-" .. format_number(x))
    else
      if type(x) == "number" then
        push_token(out, "gap-x-" .. format_number(x))
      end
      if type(y) == "number" then
        push_token(out, "gap-y-" .. format_number(y))
      end
    end
  end
end

local function margin_to_tokens(node: any, out: { string })
  local margin = node.margin
  if type(margin) ~= "table" then
    return
  end
  if type(margin.all) == "number" then
    push_token(out, "m-" .. format_number(margin.all))
  end
  if type(margin.x) == "number" then
    push_token(out, "mx-" .. format_number(margin.x))
  end
  if type(margin.y) == "number" then
    push_token(out, "my-" .. format_number(margin.y))
  end
  if type(margin.t) == "number" then
    push_token(out, "mt-" .. format_number(margin.t))
  end
  if type(margin.r) == "number" then
    push_token(out, "mr-" .. format_number(margin.r))
  end
  if type(margin.b) == "number" then
    push_token(out, "mb-" .. format_number(margin.b))
  end
  if type(margin.l) == "number" then
    push_token(out, "ml-" .. format_number(margin.l))
  end
end

local function pad_to_tokens(node: any, out: { string })
  local pad = node.pad
  if type(pad) ~= "table" then
    return
  end
  if type(pad.all) == "number" then
    push_token(out, "p-" .. format_number(pad.all))
  end
  if type(pad.x) == "number" then
    push_token(out, "px-" .. format_number(pad.x))
  end
  if type(pad.y) == "number" then
    push_token(out, "py-" .. format_number(pad.y))
  end
  if type(pad.t) == "number" then
    push_token(out, "pt-" .. format_number(pad.t))
  end
  if type(pad.r) == "number" then
    push_token(out, "pr-" .. format_number(pad.r))
  end
  if type(pad.b) == "number" then
    push_token(out, "pb-" .. format_number(pad.b))
  end
  if type(pad.l) == "number" then
    push_token(out, "pl-" .. format_number(pad.l))
  end
end

local function visual_to_tokens(node: any, out: { string })
  if is_color_token(node.bg) then
    push_token(out, "bg-" .. node.bg)
  end

  local border = node.border
  if type(border) == "table" then
    local has_w = type(border.w) == "number"
    local has_color = is_color_token(border.color)

    if has_w then
      push_token(out, "border-" .. format_number(border.w))
    elseif has_color then
      push_token(out, "border")
    end

    if has_color then
      push_token(out, "border-" .. border.color)
    end
  end

  local rounded = node.rounded
  if type(rounded) == "string" then
    if rounded == "base" then
      push_token(out, "rounded")
    elseif rounded ~= "" then
      push_token(out, "rounded-" .. rounded)
    end
  end

  if type(node.opacity) == "number" then
    local v = math.floor(node.opacity + 0.5)
    if v >= 0 and v <= 100 then
      push_token(out, "opacity-" .. tostring(v))
    end
  end

  local z = node.z
  if type(z) == "string" then
    if z == "base" or z == "dropdown" or z == "overlay" or z == "modal" or z == "popover" or z == "tooltip" then
      push_token(out, "z-" .. z)
    end
  elseif type(z) == "number" then
    local v = math.floor(z + 0.5)
    if v < 0 then
      push_token(out, "-z-" .. tostring(-v))
    else
      push_token(out, "z-" .. tostring(v))
    end
  end
end

local function text_to_tokens(node: any, out: { string })
  local text = node.text
  if type(text) ~= "table" then
    return
  end

  if is_color_token(text.color) then
    push_token(out, "text-" .. text.color)
  end

  local size = text.size
  if size == "xs" or size == "sm" or size == "base" or size == "lg" or size == "xl" or size == "2xl" or size == "3xl" then
    push_token(out, "text-" .. size)
  end

  if text.align == "left" then
    push_token(out, "text-left")
  elseif text.align == "center" then
    push_token(out, "text-center")
  elseif text.align == "right" then
    push_token(out, "text-right")
  end

  if text.wrap == "nowrap" then
    push_token(out, "text-nowrap")
  elseif text.wrap == "break-words" then
    push_token(out, "break-words")
  end

  local font = text.font
  if type(font) == "table" then
    if font.family == "ui" or font.family == "mono" or font.family == "game" or font.family == "dyslexic" then
      push_token(out, "font-" .. font.family)
    end
    if font.weight == "light" or font.weight == "normal" or font.weight == "medium" or font.weight == "semibold" or font.weight == "bold" then
      push_token(out, "font-" .. font.weight)
    end
    if font.slant == "italic" then
      push_token(out, "italic")
    elseif font.slant == "normal" then
      push_token(out, "not-italic")
    end
    if font.render == "auto" or font.render == "msdf" or font.render == "raster" then
      push_token(out, "font-render-" .. font.render)
    end
  end

  local outline = text.outline
  if type(outline) == "table" then
    if type(outline.w) == "number" then
      if is_int(outline.w) then
        push_token(out, "text-outline-" .. format_number(outline.w))
      else
        push_token(out, "text-outline-[" .. format_number(outline.w) .. "]")
      end
    end
    if is_color_token(outline.color) then
      push_token(out, "text-outline-" .. outline.color)
    end
  end
end

local function visibility_to_tokens(node: any, out: { string })
  if node.hidden == true then
    push_token(out, "hidden")
  end
  if node.clip == true then
    push_token(out, "overflow-hidden")
  end
end

local function class_extra_to_tokens(node: any, out: { string })
  local extra = node.classExtra
  if type(extra) ~= "table" then
    return
  end
  for _, tok in ipairs(extra) do
    if type(tok) == "string" and tok ~= "" and string.find(tok, "%s") == nil then
      push_token(out, tok)
    end
  end
end

local function toClass(node: any): string?
  if type(node) ~= "table" then
    return nil
  end

  local tokens: { string } = {}
  layout_to_tokens(node, tokens)
  scale_to_tokens(node, tokens)
  flex_to_tokens(node, tokens)
  margin_to_tokens(node, tokens)
  pad_to_tokens(node, tokens)
  visual_to_tokens(node, tokens)
  text_to_tokens(node, tokens)
  visibility_to_tokens(node, tokens)
  class_extra_to_tokens(node, tokens)

  if #tokens == 0 then
    return nil
  end
  return table.concat(tokens, " ")
end

local function ensure_table(root: any, key: string): any
  local v = root[key]
  if type(v) == "table" then
    return v
  end
  local t = {}
  root[key] = t
  return t
end

local function parse_bracket_number(inner: string): (number?, boolean)
  if string.sub(inner, -1) == "%" then
    local num = tonumber(string.sub(inner, 1, -2))
    if num == nil then
      return nil, false
    end
    return num, true
  end

  if string.sub(inner, -2) == "px" then
    inner = string.sub(inner, 1, -3)
  end
  local num = tonumber(inner)
  if num == nil then
    return nil, false
  end
  return num, false
end

local function parse_scale_number(inner: string): number?
  local n = tonumber(inner)
  if n == nil then
    return nil
  end
  if n ~= n or n == math.huge or n == -math.huge then
    return nil
  end
  if n < 0 then
    return nil
  end
  return n
end

local function parse_class_extra(token: string, out: { string })
  if string.sub(token, 1, 8) == "ui-path-" then
    return
  end
  if string.sub(token, 1, 6) == "__key=" then
    return
  end
  table.insert(out, token)
end

local function fromClass(class_value: string): any
  local out: any = {}
  local extra: { string } = {}

  local saw_border = false

  for tok in string.gmatch(class_value, "%S+") do
    if tok == "absolute" then
      local layout = ensure_table(out, "layout")
      layout.abs = true
    elseif string.sub(tok, 1, 7) == "anchor-" then
      local name = string.sub(tok, 8)
      local anchor = ({
        ["top-left"] = "top-left",
        ["top"] = "top",
        ["top-right"] = "top-right",
        ["left"] = "left",
        ["center"] = "center",
        ["right"] = "right",
        ["bottom-left"] = "bottom-left",
        ["bottom"] = "bottom",
        ["bottom-right"] = "bottom-right",
      })[name]
      if anchor ~= nil then
        local layout = ensure_table(out, "layout")
        layout.anchor = anchor
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 6) == "left-[" and string.sub(tok, -1) == "]" then
      local inner = string.sub(tok, 7, -2)
      local num, is_pct = parse_bracket_number(inner)
      if num ~= nil then
        local layout = ensure_table(out, "layout")
        local inset = ensure_table(layout, "inset")
        if is_pct then
          inset.left = { pct = num / 100 }
        else
          inset.left = num
        end
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 5) == "top-[" and string.sub(tok, -1) == "]" then
      local inner = string.sub(tok, 6, -2)
      local num, is_pct = parse_bracket_number(inner)
      if num ~= nil then
        local layout = ensure_table(out, "layout")
        local inset = ensure_table(layout, "inset")
        if is_pct then
          inset.top = { pct = num / 100 }
        else
          inset.top = num
        end
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 7) == "right-[" and string.sub(tok, -1) == "]" then
      local inner = string.sub(tok, 8, -2)
      local num, is_pct = parse_bracket_number(inner)
      if num ~= nil then
        local layout = ensure_table(out, "layout")
        local inset = ensure_table(layout, "inset")
        if is_pct then
          inset.right = { pct = num / 100 }
        else
          inset.right = num
        end
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 8) == "bottom-[" and string.sub(tok, -1) == "]" then
      local inner = string.sub(tok, 9, -2)
      local num, is_pct = parse_bracket_number(inner)
      if num ~= nil then
        local layout = ensure_table(out, "layout")
        local inset = ensure_table(layout, "inset")
        if is_pct then
          inset.bottom = { pct = num / 100 }
        else
          inset.bottom = num
        end
      else
        parse_class_extra(tok, extra)
      end
    elseif tok == "w-screen" then
      local layout = ensure_table(out, "layout")
      local size = ensure_table(layout, "size")
      size.w = "full"
    elseif tok == "w-full" then
      local layout = ensure_table(out, "layout")
      local size = ensure_table(layout, "size")
      size.w = "full"
    elseif tok == "w-px" then
      local layout = ensure_table(out, "layout")
      local size = ensure_table(layout, "size")
      size.w = 1
    elseif string.sub(tok, 1, 3) == "w-[" and string.sub(tok, -1) == "]" then
      local inner = string.sub(tok, 4, -2)
      local num, is_pct = parse_bracket_number(inner)
      if num ~= nil and not is_pct then
        local layout = ensure_table(out, "layout")
        local size = ensure_table(layout, "size")
        size.w = num
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 2) == "w-" then
      local suffix = string.sub(tok, 3)
      local n = parse_scale_number(suffix)
      if n ~= nil then
        local layout = ensure_table(out, "layout")
        local size = ensure_table(layout, "size")
        size.w = { tw = n }
      else
        parse_class_extra(tok, extra)
      end
    elseif tok == "h-screen" then
      local layout = ensure_table(out, "layout")
      local size = ensure_table(layout, "size")
      size.h = "full"
    elseif tok == "h-full" then
      local layout = ensure_table(out, "layout")
      local size = ensure_table(layout, "size")
      size.h = "full"
    elseif tok == "h-px" then
      local layout = ensure_table(out, "layout")
      local size = ensure_table(layout, "size")
      size.h = 1
    elseif string.sub(tok, 1, 3) == "h-[" and string.sub(tok, -1) == "]" then
      local inner = string.sub(tok, 4, -2)
      local num, is_pct = parse_bracket_number(inner)
      if num ~= nil and not is_pct then
        local layout = ensure_table(out, "layout")
        local size = ensure_table(layout, "size")
        size.h = num
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 2) == "h-" then
      local suffix = string.sub(tok, 3)
      local n = parse_scale_number(suffix)
      if n ~= nil then
        local layout = ensure_table(out, "layout")
        local size = ensure_table(layout, "size")
        size.h = { tw = n }
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 6) == "scale-" then
      local suffix = string.sub(tok, 7)
      if string.sub(suffix, 1, 1) == "[" and string.sub(suffix, -1) == "]" then
        local inner = string.sub(suffix, 2, -2)
        local n = tonumber(inner)
        if n ~= nil and n == n and n ~= math.huge and n ~= -math.huge and n > 0 then
          out.scale = n
        else
          parse_class_extra(tok, extra)
        end
      else
        local raw = tonumber(suffix)
        if raw ~= nil and raw == raw and raw ~= math.huge and raw ~= -math.huge and raw > 0 then
          if raw >= 10 then
            out.scale = raw / 100
          else
            out.scale = raw
          end
        else
          parse_class_extra(tok, extra)
        end
      end
    elseif string.sub(tok, 1, 3) == "mt-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local margin = ensure_table(out, "margin")
        margin.t = n
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "mr-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local margin = ensure_table(out, "margin")
        margin.r = n
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "mb-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local margin = ensure_table(out, "margin")
        margin.b = n
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "ml-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local margin = ensure_table(out, "margin")
        margin.l = n
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "mx-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local margin = ensure_table(out, "margin")
        margin.x = n
        margin.l = nil
        margin.r = nil
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "my-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local margin = ensure_table(out, "margin")
        margin.y = n
        margin.t = nil
        margin.b = nil
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 2) == "m-" then
      local n = parse_scale_number(string.sub(tok, 3))
      if n ~= nil then
        local margin = ensure_table(out, "margin")
        margin.all = n
        margin.x = nil
        margin.y = nil
        margin.t = nil
        margin.r = nil
        margin.b = nil
        margin.l = nil
      else
        parse_class_extra(tok, extra)
      end
    elseif tok == "flex" then
      ensure_table(out, "flex")
    elseif tok == "flex-row" then
      local flex = ensure_table(out, "flex")
      flex.dir = "row"
    elseif tok == "flex-col" then
      local flex = ensure_table(out, "flex")
      flex.dir = "col"
    elseif tok == "items-start" then
      local flex = ensure_table(out, "flex")
      flex.items = "start"
    elseif tok == "items-center" then
      local flex = ensure_table(out, "flex")
      flex.items = "center"
    elseif tok == "items-end" then
      local flex = ensure_table(out, "flex")
      flex.items = "end"
    elseif tok == "justify-start" then
      local flex = ensure_table(out, "flex")
      flex.justify = "start"
    elseif tok == "justify-center" then
      local flex = ensure_table(out, "flex")
      flex.justify = "center"
    elseif tok == "justify-end" then
      local flex = ensure_table(out, "flex")
      flex.justify = "end"
    elseif tok == "justify-between" then
      local flex = ensure_table(out, "flex")
      flex.justify = "between"
    elseif tok == "justify-around" then
      local flex = ensure_table(out, "flex")
      flex.justify = "around"
    elseif string.sub(tok, 1, 4) == "gap-" then
      local suffix = string.sub(tok, 5)
      if string.sub(suffix, 1, 2) == "x-" then
        local n = parse_scale_number(string.sub(suffix, 3))
        if n ~= nil then
          local flex = ensure_table(out, "flex")
          local gap = flex.gap
          if type(gap) == "number" then
            flex.gap = { x = n, y = gap }
          elseif type(gap) == "table" then
            gap.x = n
          else
            flex.gap = { x = n }
          end
        else
          parse_class_extra(tok, extra)
        end
      elseif string.sub(suffix, 1, 2) == "y-" then
        local n = parse_scale_number(string.sub(suffix, 3))
        if n ~= nil then
          local flex = ensure_table(out, "flex")
          local gap = flex.gap
          if type(gap) == "number" then
            flex.gap = { x = gap, y = n }
          elseif type(gap) == "table" then
            gap.y = n
          else
            flex.gap = { y = n }
          end
        else
          parse_class_extra(tok, extra)
        end
      else
        local n = parse_scale_number(suffix)
        if n ~= nil then
          local flex = ensure_table(out, "flex")
          flex.gap = n
        else
          parse_class_extra(tok, extra)
        end
      end
    elseif string.sub(tok, 1, 2) == "p-" then
      local n = parse_scale_number(string.sub(tok, 3))
      if n ~= nil then
        local pad = ensure_table(out, "pad")
        pad.all = n
        pad.x = nil
        pad.y = nil
        pad.t = nil
        pad.r = nil
        pad.b = nil
        pad.l = nil
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "px-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local pad = ensure_table(out, "pad")
        pad.x = n
        pad.l = nil
        pad.r = nil
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "py-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local pad = ensure_table(out, "pad")
        pad.y = n
        pad.t = nil
        pad.b = nil
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "pt-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local pad = ensure_table(out, "pad")
        pad.t = n
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "pr-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local pad = ensure_table(out, "pad")
        pad.r = n
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "pb-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local pad = ensure_table(out, "pad")
        pad.b = n
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "pl-" then
      local n = parse_scale_number(string.sub(tok, 4))
      if n ~= nil then
        local pad = ensure_table(out, "pad")
        pad.l = n
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "bg-" then
      local suffix = string.sub(tok, 4)
      if is_color_token(suffix) then
        out.bg = suffix
      else
        parse_class_extra(tok, extra)
      end
    elseif tok == "border" then
      saw_border = true
    elseif string.sub(tok, 1, 7) == "border-" then
      local suffix = string.sub(tok, 8)
      if string.sub(suffix, 2, 2) == "-" and (string.sub(suffix, 1, 1) == "x" or string.sub(suffix, 1, 1) == "y" or string.sub(suffix, 1, 1) == "t" or string.sub(suffix, 1, 1) == "r" or string.sub(suffix, 1, 1) == "b" or string.sub(suffix, 1, 1) == "l") then
        parse_class_extra(tok, extra)
      else
        local n = tonumber(suffix)
        if n ~= nil then
          local border = ensure_table(out, "border")
          border.w = n
        elseif suffix == "px" then
          local border = ensure_table(out, "border")
          border.w = 1
        elseif is_color_token(suffix) then
          local border = ensure_table(out, "border")
          border.color = suffix
        else
          parse_class_extra(tok, extra)
        end
      end
    elseif tok == "rounded" then
      out.rounded = "base"
    elseif string.sub(tok, 1, 8) == "rounded-" then
      local suffix = string.sub(tok, 9)
      if suffix == "none" or suffix == "sm" or suffix == "md" or suffix == "lg" or suffix == "xl" or suffix == "2xl" or suffix == "3xl" or suffix == "full" then
        out.rounded = suffix
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 8) == "opacity-" then
      local n = tonumber(string.sub(tok, 9))
      if n ~= nil then
        local v = math.floor(n + 0.5)
        if v >= 0 and v <= 100 then
          out.opacity = v
        else
          parse_class_extra(tok, extra)
        end
      else
        parse_class_extra(tok, extra)
      end
    elseif tok == "text-left" then
      local text = ensure_table(out, "text")
      text.align = "left"
    elseif tok == "text-center" then
      local text = ensure_table(out, "text")
      text.align = "center"
    elseif tok == "text-right" then
      local text = ensure_table(out, "text")
      text.align = "right"
    elseif tok == "text-nowrap" then
      local text = ensure_table(out, "text")
      text.wrap = "nowrap"
    elseif tok == "break-words" then
      local text = ensure_table(out, "text")
      text.wrap = "break-words"
    elseif tok == "italic" then
      local text = ensure_table(out, "text")
      local font = ensure_table(text, "font")
      font.slant = "italic"
    elseif tok == "not-italic" then
      local text = ensure_table(out, "text")
      local font = ensure_table(text, "font")
      font.slant = "normal"
    elseif tok == "hidden" then
      out.hidden = true
    elseif tok == "overflow-hidden" then
      out.clip = true
    elseif string.sub(tok, 1, 12) == "font-render-" then
      local suffix = string.sub(tok, 13)
      if suffix == "auto" or suffix == "msdf" or suffix == "raster" then
        local text = ensure_table(out, "text")
        local font = ensure_table(text, "font")
        font.render = suffix
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 5) == "font-" then
      local suffix = string.sub(tok, 6)
      local text = ensure_table(out, "text")
      local font = ensure_table(text, "font")
      if suffix == "ui" or suffix == "mono" or suffix == "game" or suffix == "dyslexic" then
        font.family = suffix
      elseif suffix == "light" or suffix == "normal" or suffix == "medium" or suffix == "semibold" or suffix == "bold" then
        font.weight = suffix
      else
        parse_class_extra(tok, extra)
      end
    elseif tok == "z-base" or tok == "z-dropdown" or tok == "z-overlay" or tok == "z-modal" or tok == "z-popover" or tok == "z-tooltip" then
      out.z = string.sub(tok, 3)
    elseif string.sub(tok, 1, 2) == "z-" then
      local suffix = string.sub(tok, 3)
      local n = tonumber(suffix)
      if n ~= nil then
        out.z = math.floor(n + 0.5)
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 3) == "-z-" then
      local suffix = string.sub(tok, 4)
      local n = tonumber(suffix)
      if n ~= nil then
        out.z = -math.floor(n + 0.5)
      else
        parse_class_extra(tok, extra)
      end
    elseif string.sub(tok, 1, 12) == "text-outline-" then
      local rest = string.sub(tok, 13)
      local text = ensure_table(out, "text")
      local outline = ensure_table(text, "outline")
      if string.sub(rest, 1, 1) == "[" and string.sub(rest, -1) == "]" then
        local inner = string.sub(rest, 2, -2)
        local num, _ = parse_bracket_number(inner)
        if num ~= nil then
          outline.w = num
        else
          parse_class_extra(tok, extra)
        end
      else
        local n = tonumber(rest)
        if n ~= nil then
          outline.w = n
        elseif is_color_token(rest) then
          outline.color = rest
        else
          parse_class_extra(tok, extra)
        end
      end
    elseif string.sub(tok, 1, 5) == "text-" then
      local suffix = string.sub(tok, 6)
      local text = ensure_table(out, "text")
      if suffix == "xs" or suffix == "sm" or suffix == "base" or suffix == "lg" or suffix == "xl" or suffix == "2xl" or suffix == "3xl" then
        text.size = suffix
      elseif is_color_token(suffix) then
        text.color = suffix
      else
        parse_class_extra(tok, extra)
      end
    else
      parse_class_extra(tok, extra)
    end
  end

  if saw_border then
    local border = out.border
    local keep = true
    if type(border) == "table" then
      if border.w ~= nil then
        keep = false
      elseif border.color ~= nil then
        keep = false
      end
    end
    if keep then
      table.insert(extra, "border")
    end
  end

  if #extra > 0 then
    out.classExtra = extra
  end
  return out
end

return {
  toClass = toClass,
  fromClass = fromClass,
}
