local IMAGE_SRC = "src/sprite.png"

local ids = {
  root = 1,
  card = 2,
  title = 3,
  title_text = 4,
  counter_text = 5,
  buttons_row = 6,
  inc_button = 7,
  inc_button_text = 8,
  dec_button = 9,
  dec_button_text = 10,
  icons_row = 11,
  input = 12,
  input_echo = 13,
  focus_state = 14,
  image_label = 15,
  counter_row = 16,
  input_echo_row = 17,
  focus_state_row = 18,
  image_label_row = 19,
  corner_image = 20,
  anchor_button = 21,
}

local ICON_ID_BASE = 1000

local INPUT_CLASS_BASE = "w-32 h-10 px-2 py-2 rounded-sm bg-neutral-800 border text-base text-neutral-50 text-left transition duration-50"
local INPUT_BORDER_IDLE = "border-neutral-700 hover:border-neutral-600"
local INPUT_BORDER_FOCUSED = "border-blue-400"

local t = 0
local count = 0
local shown_icons = 0
local focused = false
local anchor_index = 1

local anchor_presets = {
  { label = "top-left", class = "absolute top-0 left-0 anchor-top-left" },
  { label = "top", class = "absolute top-0 left-[240px] anchor-top" },
  { label = "top-right", class = "absolute top-0 right-0 anchor-top-right" },
  { label = "left", class = "absolute top-[96px] left-0 anchor-left" },
  { label = "center", class = "absolute top-[96px] left-[240px] anchor-center" },
  { label = "right", class = "absolute top-[96px] right-0 anchor-right" },
  { label = "bottom-left", class = "absolute bottom-0 left-0 anchor-bottom-left" },
  { label = "bottom", class = "absolute bottom-0 left-[240px] anchor-bottom" },
  { label = "bottom-right", class = "absolute bottom-0 right-0 anchor-bottom-right" },
}

local function set_input_focus_style(is_focused)
  local border = INPUT_BORDER_IDLE
  if is_focused then
    border = INPUT_BORDER_FOCUSED
  end
  ui.set_class(ids.input, string.format("%s %s", INPUT_CLASS_BASE, border))
end

local function set_counter()
  ui.set_text(ids.counter_text, string.format("Count: %d", count))
end

local function set_corner_anchor()
  local preset = anchor_presets[anchor_index]
  ui.set_class(ids.anchor_button, string.format("%s w-12 h-12 bg-neutral-900 z-10", preset.class))
end

local function set_anchor_label()
  local preset = anchor_presets[anchor_index]
  ui.set_text(ids.image_label, string.format("Image: %s (anchor: %s)", IMAGE_SRC, preset.label))
end

local function create_icon(i)
  local icon_id = ICON_ID_BASE + i
  ui.create("image", icon_id, ids.icons_row, nil)
  ui.set_class(icon_id, "w-10 h-10 bg-neutral-900")
  ui.set_visual(icon_id, { background = 0x0f172aff })
  ui.set_image(icon_id, { src = IMAGE_SRC, tint = 0x22c55eff, opacity = 1.0 })
end

local function sync_icons()
  if count > shown_icons then
    for i = shown_icons + 1, count do
      create_icon(i)
    end
    shown_icons = count
    return
  end

  if count < shown_icons then
    for i = shown_icons, count + 1, -1 do
      ui.remove(ICON_ID_BASE + i)
    end
    shown_icons = count
    return
  end
end

local function build_ui()
  ui.reset()

  ui.create("div", ids.root, nil, nil)
  ui.set_class(ids.root, "w-full h-full flex flex-col justify-center items-center bg-neutral-900 p-6")

  ui.create("div", ids.card, ids.root, nil)
  ui.set_class(ids.card, "w-[520px] flex flex-col gap-2 bg-neutral-800 border border-neutral-700 rounded-2xl p-3")
  ui.set_visual(ids.card, { background = 0x020617ff, cornerRadius = 18 })

  ui.create("button", ids.anchor_button, ids.card, nil)
  set_corner_anchor()
  ui.set_visual(ids.anchor_button, { background = 0x0f172aff, cornerRadius = 8, opacity = 0.0 })
  ui.listen(ids.anchor_button, "click")

  ui.create("image", ids.corner_image, ids.anchor_button, nil)
  ui.set_class(ids.corner_image, "w-full h-full")
  ui.set_image(ids.corner_image, { src = IMAGE_SRC, opacity = 1.0 })

  ui.create("h1", ids.title, ids.card, nil)
  ui.set_class(ids.title, "text-2xl text-neutral-50 text-outline-black text-outline-[2px] font-bold text-nowrap")
  ui.create("text", ids.title_text, ids.title, nil)
  ui.set_text(ids.title_text, "UI Features (Starter)")

  ui.create("p", ids.counter_row, ids.card, nil)
  ui.set_class(ids.counter_row, "w-full text-base text-neutral-200 text-nowrap")
  ui.create("text", ids.counter_text, ids.counter_row, nil)
  set_counter()

  ui.create("div", ids.buttons_row, ids.card, nil)
  ui.set_class(ids.buttons_row, "flex flex-row gap-3 items-center")

  ui.create("button", ids.inc_button, ids.buttons_row, nil)
  ui.set_class(ids.inc_button, "px-4 py-2 rounded-lg border-blue-500 bg-emerald-500 hover:bg-emerald-800 text-base text-neutral-900 font-bold transition duration-100 ease-quad ease-in-out cursor-pointer")
  ui.set_visual(ids.inc_button, { background = 0x10b981ff, cornerRadius = 10 })
  ui.listen(ids.inc_button, "click")

  ui.create("text", ids.inc_button_text, ids.inc_button, nil)
  ui.set_text(ids.inc_button_text, "+1")

  ui.create("button", ids.dec_button, ids.buttons_row, nil)
  ui.set_class(ids.dec_button, "px-4 py-2 rounded-lg bg-neutral-700 hover:bg-neutral-500 text-base text-neutral-100 font-bold transition duration-100 ease-sine ease-in-out cursor-pointer")
  ui.set_visual(ids.dec_button, { background = 0x1f2937ff, cornerRadius = 10 })
  ui.listen(ids.dec_button, "click")

  ui.create("text", ids.dec_button_text, ids.dec_button, nil)
  ui.set_text(ids.dec_button_text, "-1")

  ui.create("div", ids.icons_row, ids.card, nil)
  ui.set_class(ids.icons_row, "flex flex-row flex-wrap gap-2 items-center")

  ui.create("input", ids.input, ids.card, nil)
  set_input_focus_style(false)
  ui.listen(ids.input, "input")
  ui.listen(ids.input, "focus")
  ui.listen(ids.input, "blur")
  ui.listen(ids.input, "enter")

  ui.create("p", ids.input_echo_row, ids.card, nil)
  ui.set_class(ids.input_echo_row, "w-full text-sm text-neutral-300 break-words")
  ui.create("text", ids.input_echo, ids.input_echo_row, nil)
  ui.set_text(ids.input_echo, "Input: ")

  ui.create("p", ids.focus_state_row, ids.card, nil)
  ui.set_class(ids.focus_state_row, "w-full text-sm text-neutral-400 text-nowrap")
  ui.create("text", ids.focus_state, ids.focus_state_row, nil)
  ui.set_text(ids.focus_state, "Focus: false")

  ui.create("p", ids.image_label_row, ids.card, nil)
  ui.set_class(ids.image_label_row, "w-full text-xs text-neutral-500 break-words")
  ui.create("text", ids.image_label, ids.image_label_row, nil)
  set_anchor_label()

  sync_icons()
end

function init()
  ui.log("ui_features starter init")
  build_ui()
end

function update(dt, input)
  t = t + dt
  local wave = math.sin(t * 5)
  local scale = 0.5 + wave * 0.5
  ui.set_transform(ids.anchor_button, { anchorX = 0.5, anchorY = 0.5, scale = scale })
  ui.set_transform(ids.corner_image, { anchorX = 0.5, anchorY = 0.5, scale = scale })
end

function on_event(kind, id, detail)
  if kind == "click" and id == ids.inc_button then
    count = count + 1
    set_counter()
    sync_icons()
    return
  end

  if kind == "click" and id == ids.dec_button then
    count = math.max(0, count - 1)
    set_counter()
    sync_icons()
    return
  end

  if kind == "click" and id == ids.anchor_button then
    anchor_index = anchor_index + 1
    if anchor_index > #anchor_presets then
      anchor_index = 1
    end
    set_corner_anchor()
    set_anchor_label()
    return
  end

  if kind == "input" and id == ids.input then
    ui.set_text(ids.input_echo, string.format("Input: %s", detail))
    return
  end

  if kind == "focus" and id == ids.input then
    focused = true
    ui.set_text(ids.focus_state, "Focus: true")
    set_input_focus_style(true)
    return
  end

  if kind == "blur" and id == ids.input then
    focused = false
    ui.set_text(ids.focus_state, "Focus: false")
    set_input_focus_style(false)
    return
  end

  if kind == "enter" and id == ids.input then
    ui.set_text(ids.input_echo, string.format("Submit: %s", detail))
    ui.set_input(ids.input, "")
    return
  end
end
