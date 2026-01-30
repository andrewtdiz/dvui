-- Monolithic retained-UI feature demo.
-- This script is meant to exercise the currently-implemented UI_FEATURES.md items.

local ids = {}
local next_id = 1

local function alloc(name)
  local id = next_id
  next_id = next_id + 1
  ids[name] = id
  return id
end

alloc("root")
alloc("main")
alloc("left")
alloc("right")

alloc("title")
alloc("title_text")
alloc("subtitle")
alloc("subtitle_text")

alloc("playground")
alloc("pg_label")
alloc("pg_label_text")
alloc("sq_center")
alloc("sq_corner")
alloc("z_badge")
alloc("z_badge_text")
alloc("clip_bar")
alloc("pg_info")
alloc("pg_info_text")

alloc("img")
alloc("img_label")
alloc("img_label_text")

alloc("events_panel")
alloc("click_row")
alloc("click_btn")
alloc("click_btn_text")
alloc("click_count")
alloc("click_count_text")

alloc("hover_row")
alloc("hover_target")
alloc("hover_target_text")
alloc("hover_state")
alloc("hover_state_text")

alloc("input_row")
alloc("input_label")
alloc("input_label_text")
alloc("input")
alloc("input_echo")
alloc("input_echo_text")
alloc("focus_state")
alloc("focus_state_text")

alloc("scroll_panel")
alloc("scroll_label")
alloc("scroll_label_text")
alloc("scroll")
alloc("scroll_content")
alloc("scroll_state")
alloc("scroll_state_text")

-- Scroll list item ids (div + label text)
local item_ids = {}
for i = 1, 28 do
  local row = alloc("item_row_" .. tostring(i))
  local label = alloc("item_label_" .. tostring(i))
  item_ids[i] = { row = row, label = label }
end

local t = 0
local clicks = 0
local hovered = false
local focused = false
local last_scroll_detail = ""

local function build_ui()
  ui.reset()

  ui.create("div", ids.root, nil, nil)
  ui.set_class(ids.root, "w-full h-full bg-slate-900 flex flex-col justify-center items-center p-6")

  ui.create("div", ids.main, ids.root, nil)
  ui.set_class(ids.main, "flex flex-row gap-6")

  ui.create("div", ids.left, ids.main, nil)
  ui.set_class(ids.left, "w-[520px] flex flex-col gap-4")

  ui.create("div", ids.right, ids.main, nil)
  ui.set_class(ids.right, "w-[520px] flex flex-col gap-4")

  -- Header
  ui.create("h1", ids.title, ids.left, nil)
  ui.set_class(ids.title, "text-3xl font-bold text-slate-50 text-center")

  ui.create("text", ids.title_text, ids.title, nil)
  ui.set_text(ids.title_text, "UI Feature Demo")
  ui.set_class(ids.title_text, "text-3xl font-bold text-slate-50 text-center")

  ui.create("p", ids.subtitle, ids.left, nil)
  ui.set_class(ids.subtitle, "text-sm text-slate-300 text-center")

  ui.create("text", ids.subtitle_text, ids.subtitle, nil)
  ui.set_text(ids.subtitle_text, "Transforms, z-index, clipping, images, scroll, and per-node events.")
  ui.set_class(ids.subtitle_text, "text-sm text-slate-300 text-center")

  -- Playground: absolute positioning + clipping + z-index + transforms
  ui.create("div", ids.playground, ids.left, nil)
  ui.set_class(ids.playground, "w-full h-[320px] bg-slate-950 rounded-xl overflow-hidden border border-slate-700")

  ui.create("div", ids.pg_label, ids.playground, nil)
  ui.create("text", ids.pg_label_text, ids.pg_label, nil)
  ui.set_class(ids.pg_label, "absolute left-[12px] top-[10px] px-3 py-1 rounded-full bg-slate-800")
  ui.set_visual(ids.pg_label, { background = 0x1f2937ff, cornerRadius = 9999 })
  ui.set_text(ids.pg_label_text, "div: pos/size/anchor/rotation/opacity/z/clip")
  ui.set_class(ids.pg_label_text, "text-xs text-slate-200")

  -- Moving bar that gets clipped by overflow-hidden.
  ui.create("div", ids.clip_bar, ids.playground, nil)
  ui.set_class(ids.clip_bar, "absolute left-[-160px] top-[230px] w-[820px] h-[120px] bg-emerald-400 opacity-40 z-0")
  ui.set_visual(ids.clip_bar, { background = 0x34d399ff, opacity = 0.35 })

  -- Two squares with different pivot/anchors.
  ui.create("div", ids.sq_center, ids.playground, nil)
  ui.set_class(ids.sq_center, "absolute left-[70px] top-[70px] w-[140px] h-[140px] bg-indigo-500 rounded-xl opacity-80 z-[10]")
  ui.set_visual(ids.sq_center, { background = 0x6366f1ff, cornerRadius = 16, opacity = 0.8 })

  ui.create("div", ids.sq_corner, ids.playground, nil)
  ui.set_class(ids.sq_corner, "absolute left-[250px] top-[70px] w-[140px] h-[140px] bg-amber-400 rounded-xl opacity-80 z-[5]")
  ui.set_visual(ids.sq_corner, { background = 0xfbbf24ff, cornerRadius = 16, opacity = 0.8 })

  -- Z-index badge that always stays on top.
  ui.create("div", ids.z_badge, ids.playground, nil)
  ui.set_class(ids.z_badge, "absolute right-[12px] top-[10px] px-3 py-1 rounded-full bg-slate-50 z-[50]")
  ui.set_visual(ids.z_badge, { background = 0xf8fafcff, cornerRadius = 9999 })

  ui.create("text", ids.z_badge_text, ids.z_badge, nil)
  ui.set_text(ids.z_badge_text, "z:[50]")
  ui.set_class(ids.z_badge_text, "text-xs text-slate-900 font-bold")

  -- Image: src + tint + opacity (separate from background).
  ui.create("image", ids.img, ids.playground, nil)
  ui.set_class(ids.img, "absolute left-[400px] top-[120px] w-[92px] h-[92px] rounded-lg z-[20]")
  ui.set_visual(ids.img, { cornerRadius = 12, opacity = 1.0 })
  ui.set_image(ids.img, { src = "favicon.png", tint = 0x22c55eff, opacity = 0.65 })

  ui.create("div", ids.img_label, ids.playground, nil)
  ui.set_class(ids.img_label, "absolute left-[365px] top-[220px] px-3 py-1 rounded-full bg-slate-800 z-[20]")
  ui.set_visual(ids.img_label, { background = 0x1f2937ff, cornerRadius = 9999 })

  ui.create("text", ids.img_label_text, ids.img_label, nil)
  ui.set_text(ids.img_label_text, "image: src+tint+opacity")
  ui.set_class(ids.img_label_text, "text-xs text-slate-200")

  ui.create("div", ids.pg_info, ids.playground, nil)
  ui.set_class(ids.pg_info, "absolute left-[12px] top-[40px] w-[230px] px-3 py-2 rounded-lg bg-slate-900 opacity-90 z-[30]")
  ui.set_visual(ids.pg_info, { background = 0x0f172aff, cornerRadius = 10, opacity = 0.9 })

  ui.create("text", ids.pg_info_text, ids.pg_info, nil)
  ui.set_text(ids.pg_info_text, "Center square pivots at (0.5,0.5).\nGold square pivots at (0,0).\nScroll the right panel to test scrollbars.")
  ui.set_class(ids.pg_info_text, "text-xs text-slate-200 break-words")

  -- Events panel
  ui.create("div", ids.events_panel, ids.left, nil)
  ui.set_class(ids.events_panel, "w-full bg-slate-950 rounded-xl border border-slate-700 p-4 flex flex-col gap-3")

  ui.create("div", ids.click_row, ids.events_panel, nil)
  ui.set_class(ids.click_row, "flex flex-row items-center justify-between gap-3")

  ui.create("button", ids.click_btn, ids.click_row, nil)
  ui.set_class(ids.click_btn, "px-4 py-2 rounded-lg bg-emerald-500 hover:bg-emerald-400 cursor-pointer")
  ui.set_visual(ids.click_btn, { background = 0x10b981ff, cornerRadius = 10 })
  ui.listen(ids.click_btn, "click")

  ui.create("text", ids.click_btn_text, ids.click_btn, nil)
  ui.set_text(ids.click_btn_text, "Click")
  ui.set_class(ids.click_btn_text, "text-sm text-slate-900 font-bold")

  ui.create("div", ids.click_count, ids.click_row, nil)
  ui.set_class(ids.click_count, "px-3 py-2 rounded-lg bg-slate-800")
  ui.set_visual(ids.click_count, { background = 0x1f2937ff, cornerRadius = 10 })

  ui.create("text", ids.click_count_text, ids.click_count, nil)
  ui.set_text(ids.click_count_text, "Clicks: 0")
  ui.set_class(ids.click_count_text, "text-sm text-slate-200")

  ui.create("div", ids.hover_row, ids.events_panel, nil)
  ui.set_class(ids.hover_row, "flex flex-col gap-2")

  ui.create("div", ids.hover_target, ids.hover_row, nil)
  ui.set_class(ids.hover_target, "h-[44px] rounded-lg bg-slate-800 px-4 flex flex-row items-center justify-between cursor-pointer")
  ui.set_visual(ids.hover_target, { background = 0x1f2937ff, cornerRadius = 10 })
  ui.listen(ids.hover_target, "mouseenter")
  ui.listen(ids.hover_target, "mouseleave")

  ui.create("text", ids.hover_target_text, ids.hover_target, nil)
  ui.set_text(ids.hover_target_text, "Hover Me (mouseenter/mouseleave)")
  ui.set_class(ids.hover_target_text, "text-sm text-slate-200")

  ui.create("div", ids.hover_state, ids.hover_row, nil)
  ui.set_class(ids.hover_state, "px-3 py-2 rounded-lg bg-slate-900")
  ui.set_visual(ids.hover_state, { background = 0x0f172aff, cornerRadius = 10 })

  ui.create("text", ids.hover_state_text, ids.hover_state, nil)
  ui.set_text(ids.hover_state_text, "Hover: false")
  ui.set_class(ids.hover_state_text, "text-xs text-slate-300")

  ui.create("div", ids.input_row, ids.events_panel, nil)
  ui.set_class(ids.input_row, "flex flex-col gap-2")

  ui.create("div", ids.input_label, ids.input_row, nil)
  ui.set_class(ids.input_label, "flex flex-row items-center justify-between")

  ui.create("text", ids.input_label_text, ids.input_label, nil)
  ui.set_text(ids.input_label_text, "Input")
  ui.set_class(ids.input_label_text, "text-sm text-slate-200 font-bold")

  ui.create("div", ids.focus_state, ids.input_label, nil)
  ui.set_class(ids.focus_state, "px-3 py-1 rounded-lg bg-slate-800")
  ui.set_visual(ids.focus_state, { background = 0x1f2937ff, cornerRadius = 10 })

  ui.create("text", ids.focus_state_text, ids.focus_state, nil)
  ui.set_text(ids.focus_state_text, "Focus: false")
  ui.set_class(ids.focus_state_text, "text-xs text-slate-200")

  ui.create("input", ids.input, ids.input_row, nil)
  ui.set_class(ids.input, "h-[40px] w-full px-4 rounded-lg bg-slate-800 border border-slate-600 text-base text-slate-50")
  ui.listen(ids.input, "input")
  ui.listen(ids.input, "focus")
  ui.listen(ids.input, "blur")

  ui.create("div", ids.input_echo, ids.input_row, nil)
  ui.set_class(ids.input_echo, "px-3 py-2 rounded-lg bg-slate-900")
  ui.set_visual(ids.input_echo, { background = 0x0f172aff, cornerRadius = 10 })

  ui.create("text", ids.input_echo_text, ids.input_echo, nil)
  ui.set_text(ids.input_echo_text, "Input: ")
  ui.set_class(ids.input_echo_text, "text-xs text-slate-300 break-words")

  -- Scroll demo (right panel)
  ui.create("div", ids.scroll_panel, ids.right, nil)
  ui.set_class(ids.scroll_panel, "w-full bg-slate-950 rounded-xl border border-slate-700 p-4 flex flex-col gap-3")

  ui.create("div", ids.scroll_label, ids.scroll_panel, nil)
  ui.set_class(ids.scroll_label, "flex flex-row items-center justify-between")

  ui.create("text", ids.scroll_label_text, ids.scroll_label, nil)
  ui.set_text(ids.scroll_label_text, "overflow: wheel/touch + scrollbars")
  ui.set_class(ids.scroll_label_text, "text-sm text-slate-200 font-bold")

  ui.create("div", ids.scroll_state, ids.scroll_label, nil)
  ui.set_class(ids.scroll_state, "px-3 py-1 rounded-lg bg-slate-800")
  ui.set_visual(ids.scroll_state, { background = 0x1f2937ff, cornerRadius = 10 })

  ui.create("text", ids.scroll_state_text, ids.scroll_state, nil)
  ui.set_text(ids.scroll_state_text, "Scroll: 0,0")
  ui.set_class(ids.scroll_state_text, "text-xs text-slate-200")

  ui.create("div", ids.scroll, ids.scroll_panel, nil)
  ui.set_class(ids.scroll, "w-full h-[420px] bg-slate-900 rounded-lg overflow-hidden")
  ui.set_visual(ids.scroll, { background = 0x0b1220ff, cornerRadius = 12 })
  ui.set_scroll(ids.scroll, { enabled = true, autoCanvas = true })
  ui.listen(ids.scroll, "scroll")

  -- Content wider than viewport to force horizontal scrolling.
  ui.create("div", ids.scroll_content, ids.scroll, nil)
  ui.set_class(ids.scroll_content, "flex flex-col gap-3 p-3 w-[760px]")

  for i = 1, 28 do
    local row_id = item_ids[i].row
    local label_id = item_ids[i].label

    ui.create("div", row_id, ids.scroll_content, nil)
    ui.set_class(row_id, "h-[44px] rounded-lg bg-slate-800 px-4 flex flex-row justify-between items-center")

    ui.create("text", label_id, row_id, nil)
    ui.set_text(label_id, string.format("Item %d: This is a long row to test horizontal scrolling.", i))
    ui.set_class(label_id, "text-sm text-slate-200")
  end
end

function init()
  ui.log("ui_features.luau init")
  build_ui()
end

function update(dt, input)
  t = t + dt

  local rot = t * 1.4
  local wobble = math.sin(t * 2.0) * 18

  -- Rotate around different pivots.
  ui.set_transform(ids.sq_center, { anchorX = 0.5, anchorY = 0.5, rotation = rot, translateY = wobble })
  ui.set_transform(ids.sq_corner, { anchorX = 0.0, anchorY = 0.0, rotation = -rot, translateY = -wobble * 0.5 })

  -- Make the clipped bar slide to demonstrate overflow-hidden/clipChildren.
  ui.set_transform(ids.clip_bar, { translateX = math.sin(t * 1.1) * 80 })

  -- Image transform: scale + rotation.
  local s = 0.9 + (math.sin(t * 2.6) * 0.08)
  ui.set_transform(ids.img, { anchorX = 0.5, anchorY = 0.5, rotation = rot * 0.5, scaleX = s, scaleY = s })

  -- Update a live text block to verify wrapping.
  ui.set_text(ids.pg_info_text, string.format(
    "Mouse: (%.0f, %.0f)\n" ..
      "Center pivot (0.5,0.5) vs corner pivot (0,0).\n" ..
      "Scroll detail: %s",
    input.mouseX,
    input.mouseY,
    last_scroll_detail
  ))
end

function on_event(kind, id, detail)
  if kind == "click" and id == ids.click_btn then
    clicks = clicks + 1
    ui.set_text(ids.click_count_text, string.format("Clicks: %d", clicks))
  end

  if kind == "mouseenter" and id == ids.hover_target then
    hovered = true
    ui.set_text(ids.hover_state_text, "Hover: true")
  elseif kind == "mouseleave" and id == ids.hover_target then
    hovered = false
    ui.set_text(ids.hover_state_text, "Hover: false")
  end

  if kind == "input" and id == ids.input then
    ui.set_text(ids.input_echo_text, string.format("Input: %s", detail))
  end

  if kind == "focus" and id == ids.input then
    focused = true
    ui.set_text(ids.focus_state_text, "Focus: true")
  elseif kind == "blur" and id == ids.input then
    focused = false
    ui.set_text(ids.focus_state_text, "Focus: false")
  end

  if kind == "scroll" and id == ids.scroll then
    -- detail is a JSON-ish string from Zig, keep it as-is.
    last_scroll_detail = detail
    ui.set_text(ids.scroll_state_text, "Scroll: " .. detail)
  end
end
