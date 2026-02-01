local ids = {
  root = 1,
  panel = 2,
  title = 3,
  title_text = 4,
  options = 5,
  play_button = 6,
  play_text = 7,
  load_button = 8,
  load_text = 9,
  settings_button = 10,
  settings_text = 11,
  quit_button = 12,
  quit_text = 13,
  divider = 14,
}

local ROOT_CLASS = "w-full h-full flex flex-col justify-center items-center bg-neutral-950"
local PANEL_CLASS = "w-[320px] flex flex-col items-center gap-6 bg-neutral-900 border border-neutral-700 rounded-3xl p-10"
local TITLE_CLASS = "text-4xl text-neutral-50 text-outline-black text-outline-[1px] font-game text-center text-nowrap"
local DIVIDER_CLASS = "w-full h-px bg-neutral-700 opacity-60"
local OPTIONS_CLASS = "w-full flex flex-col gap-4 items-center"
local OPTION_CLASS = "w-full px-6 py-3 rounded-lg flex items-center justify-center text-lg text-neutral-200 hover:text-amber-300 hover:bg-neutral-800 text-outline-black text-outline-[1px] text-center font-game cursor-pointer transition duration"

local function create_menu_option(button_id, text_id, parent_id, label)
  ui.create("button", button_id, parent_id, nil)
  ui.set_class(button_id, OPTION_CLASS)
  ui.set_visual(button_id, { background = 0x0f172a00, cornerRadius = 10 })
  ui.listen(button_id, "click")
  ui.create("text", text_id, button_id, nil)
  ui.set_text(text_id, label)
end

local function build_ui()
  ui.reset()

  ui.create("div", ids.root, nil, nil)
  ui.set_class(ids.root, ROOT_CLASS)

  ui.create("div", ids.panel, ids.root, nil)
  ui.set_class(ids.panel, PANEL_CLASS)

  ui.create("h1", ids.title, ids.panel, nil)
  ui.set_class(ids.title, TITLE_CLASS)
  ui.create("text", ids.title_text, ids.title, nil)
  ui.set_text(ids.title_text, "Main Menu")

  ui.create("div", ids.divider, ids.panel, nil)
  ui.set_class(ids.divider, DIVIDER_CLASS)

  ui.create("div", ids.options, ids.panel, nil)
  ui.set_class(ids.options, OPTIONS_CLASS)

  create_menu_option(ids.play_button, ids.play_text, ids.options, "Play Game")
  create_menu_option(ids.load_button, ids.load_text, ids.options, "Load Game")
  create_menu_option(ids.settings_button, ids.settings_text, ids.options, "Settings")
  create_menu_option(ids.quit_button, ids.quit_text, ids.options, "Quit")
end

function init()
  build_ui()
end

function update(dt, input)
end

function on_event(kind, id, detail)
end
