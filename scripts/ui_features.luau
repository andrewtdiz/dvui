-- Starter UI example.
-- Full end-to-end feature demo lives in: scripts/ui_features_all.luau

-- Put your image file in the repo and point this at it (path is relative to process cwd).
-- Example: copy Image #1 to `src/sprite.png`.
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
}

local ICON_ID_BASE = 1000

local INPUT_CLASS_BASE = "w-32 h-10 px-4 py-2 rounded-lg bg-slate-800 border text-base text-slate-50 text-left"
local INPUT_BORDER_IDLE = "border-slate-700"
local INPUT_BORDER_FOCUSED = "border-emerald-400"

local t = 0
local count = 0
local shown_icons = 0
local focused = false

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

local function create_icon(i)
  local icon_id = ICON_ID_BASE + i
  ui.create("image", icon_id, ids.icons_row, nil)
  ui.set_class(icon_id, "w-10 h-10 bg-slate-900")
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
  ui.set_class(ids.root, "w-full h-full flex flex-col justify-center items-center bg-slate-900 p-6")

  ui.create("div", ids.card, ids.root, nil)
  ui.set_class(ids.card, "w-[520px] flex flex-col gap-2 bg-slate-950 border border-slate-700 rounded-2xl p-3")
  ui.set_visual(ids.card, { background = 0x020617ff, cornerRadius = 18 })

  ui.create("h1", ids.title, ids.card, nil)
  ui.set_class(ids.title, "text-2xl text-slate-50 font-bold font-game text-nowrap")
  ui.create("text", ids.title_text, ids.title, nil)
  ui.set_text(ids.title_text, "UI Features (Starter)")

  ui.create("p", ids.counter_row, ids.card, nil)
  ui.set_class(ids.counter_row, "w-full text-base text-slate-200 text-nowrap")
  ui.create("text", ids.counter_text, ids.counter_row, nil)
  set_counter()

  ui.create("div", ids.buttons_row, ids.card, nil)
  ui.set_class(ids.buttons_row, "flex flex-row gap-3 items-center")

  ui.create("button", ids.inc_button, ids.buttons_row, nil)
  ui.set_class(ids.inc_button, "px-4 py-2 rounded-lg border-blue-500 bg-emerald-500 hover:bg-emerald-800 text-base text-slate-900 font-bold transition duration-100 ease-quad ease-in-out cursor-pointer")
  ui.set_visual(ids.inc_button, { background = 0x10b981ff, cornerRadius = 10 })
  ui.listen(ids.inc_button, "click")

  ui.create("text", ids.inc_button_text, ids.inc_button, nil)
  ui.set_text(ids.inc_button_text, "+1")

  ui.create("button", ids.dec_button, ids.buttons_row, nil)
  ui.set_class(ids.dec_button, "px-4 py-2 rounded-lg bg-slate-800 hover:bg-slate-500 text-base text-slate-100 font-bold transition-colors duration-100 ease-sine ease-in-out cursor-pointer")
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
  ui.set_class(ids.input_echo_row, "w-full text-sm text-slate-300 break-words")
  ui.create("text", ids.input_echo, ids.input_echo_row, nil)
  ui.set_text(ids.input_echo, "Input: ")

  ui.create("p", ids.focus_state_row, ids.card, nil)
  ui.set_class(ids.focus_state_row, "w-full text-sm text-slate-400 text-nowrap")
  ui.create("text", ids.focus_state, ids.focus_state_row, nil)
  ui.set_text(ids.focus_state, "Focus: false")

  ui.create("p", ids.image_label_row, ids.card, nil)
  ui.set_class(ids.image_label_row, "w-full text-xs text-slate-500 break-words")
  ui.create("text", ids.image_label, ids.image_label_row, nil)
  ui.set_text(ids.image_label, string.format("Image: %s", IMAGE_SRC))

  sync_icons()
end

function init()
  ui.log("ui_features starter init")
  build_ui()
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
