local ids = {
  root = 1,
  header = 2,
  title = 3,
  subtitle = 4,
  stats = 5,
  counter = 6,
  button = 7,
  buttonLabel = 8,
}

local ticks = 0
local count = 0
local last_down = false

local function build_ui()
  ui.reset()

  ui.create("div", ids.root, nil, nil)
  ui.set_class(ids.root, "w-full h-full flex flex-col justify-center items-center gap-6 bg-slate-900")

  ui.create("div", ids.header, ids.root, nil)
  ui.set_class(ids.header, "flex flex-col items-center gap-2 px-8 py-6 bg-slate-800 rounded-2xl")
  ui.set_visual(ids.header, { cornerRadius = 18, background = 0x1e293bff, clipChildren = true })

  ui.create("h1", ids.title, ids.header, nil)
  ui.set_text(ids.title, "Luau Retained UI")
  ui.set_class(ids.title, "text-3xl text-slate-50 text-center")

  ui.create("p", ids.subtitle, ids.header, nil)
  ui.set_text(ids.subtitle, "Animated text + event-driven button")
  ui.set_class(ids.subtitle, "text-base text-slate-200 text-center")

  ui.create("div", ids.stats, ids.header, nil)
  ui.set_class(ids.stats, "flex flex-col items-center gap-1")

  ui.create("text", ids.counter, ids.stats, nil)
  ui.set_text(ids.counter, "Clicks: 0")
  ui.set_class(ids.counter, "text-lg text-emerald-300")

  ui.create("button", ids.button, ids.header, nil)
  ui.set_class(ids.button, "px-6 py-3 bg-emerald-500 rounded-lg text-slate-900")
  ui.set_visual(ids.button, { background = 0x10b981ff, cornerRadius = 10 })
  ui.listen(ids.button, "click")

  ui.create("text", ids.buttonLabel, ids.button, nil)
  ui.set_text(ids.buttonLabel, "Click Me")
  ui.set_class(ids.buttonLabel, "text-base text-slate-900")
end

function init()
  ui.log("luau demo init")
  build_ui()
end

function update(dt, input)
  ticks = ticks + dt
  local wave = math.sin(ticks * 2.1)
  local offset = wave * 12
  ui.set_transform(ids.header, { translateY = offset })

  local shimmer = math.floor((wave * 0.5 + 0.5) * 90)
  ui.set_text(ids.subtitle, string.format("Animated text + event-driven button (%d)", shimmer))

  if input.mouseDown and not last_down then
    local center_x = input.width * 0.5
    local center_y = input.height * 0.5
    ui.set_transform(ids.header, { translateX = input.mouseX - center_x, translateY = offset + (input.mouseY - center_y) * 0.05 })
  end
  last_down = input.mouseDown
end

function on_event(kind, id, detail)
  if kind == "click" and id == ids.button then
    count = count + 1
    ui.set_text(ids.counter, string.format("Clicks: %d", count))
  end
end
