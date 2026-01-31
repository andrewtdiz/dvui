local function Create(tag)
  return function(spec)
    return {
      tag = tag,
      class = spec.class,
      props = spec.props,
      children = spec.children,
    }
  end
end

local function For(spec)
  local out = {}
  for i, item in ipairs(spec.each) do
    out[i] = spec.children(item, i)
  end
  return out
end

local menuOptions = { "Play Game", "Load Game", "Settings", "Quit" }

local function UiFeatures()
  return Create("div"){
    class = "w-full h-full flex flex-col justify-center items-center bg-neutral-950",
    children = {
      Create("div"){
        class = "w-[320px] flex flex-col items-center gap-6 bg-neutral-900 border border-neutral-700 rounded-3xl p-10",
        children = {
          Create("h1"){
            class = "text-4xl text-neutral-50 text-outline-black text-outline-[1px] font-game text-center text-nowrap",
            children = { "Main Menu" },
          },
          Create("div"){
            class = "w-full h-px bg-neutral-700 opacity-60",
          },
          Create("div"){
            class = "w-full flex flex-col gap-4 items-center",
            children = For{
              each = menuOptions,
              children = function(label)
                return Create("button"){
                  class = "w-full px-6 py-3 rounded-lg flex items-center justify-center text-lg text-neutral-200 hover:text-amber-300 hover:bg-neutral-800 text-outline-black text-outline-[1px] text-center font-game cursor-pointer transition duration",
                  props = { type = "button" },
                  children = { label },
                }
              end,
            },
          },
        },
      },
    },
  }
end

local next_id = 1

local function alloc_id()
  local id = next_id
  next_id = next_id + 1
  return id
end

local function apply_props(id, props)
  if props == nil then
    return
  end

  if props.visual ~= nil then
    ui.set_visual(id, props.visual)
  end
  if props.transform ~= nil then
    ui.set_transform(id, props.transform)
  end
  if props.scroll ~= nil then
    ui.set_scroll(id, props.scroll)
  end
  if props.anchor ~= nil then
    ui.set_anchor(id, props.anchor)
  end
  if props.image ~= nil then
    ui.set_image(id, props.image)
  end
  if props.src ~= nil then
    ui.set_src(id, props.src)
  end

  local listen = props.listen
  if listen ~= nil then
    for _, event_name in ipairs(listen) do
      ui.listen(id, event_name)
    end
  end
end

local function listen_defaults(id, tag)
  if tag == "button" then
    ui.listen(id, "click")
    ui.listen(id, "mouseenter")
    ui.listen(id, "mouseleave")
    return
  end

  if tag == "input" then
    ui.listen(id, "input")
    ui.listen(id, "focus")
    ui.listen(id, "blur")
    ui.listen(id, "enter")
  end
end

local function mount(node, parent_id)
  local node_type = type(node)
  if node_type == "string" then
    local id = alloc_id()
    ui.create("text", id, parent_id, nil)
    ui.set_text(id, node)
    return id
  end

  if node_type ~= "table" then
    return nil
  end

  local tag = node.tag
  if tag == nil then
    for _, child in ipairs(node) do
      mount(child, parent_id)
    end
    return nil
  end

  local id = alloc_id()
  ui.create(tag, id, parent_id, nil)
  if node.class ~= nil then
    ui.set_class(id, node.class)
  end
  apply_props(id, node.props)
  listen_defaults(id, tag)
  if node.children ~= nil then
    mount(node.children, id)
  end
  return id
end

function init()
  ui.reset()
  next_id = 1
  mount(UiFeatures(), nil)
end

function update(dt, input)
end

function on_event(kind, id, detail)
end
