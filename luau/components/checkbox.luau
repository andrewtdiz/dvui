local SolidLuau = require("solidluau")
local cn = require("luau/ui/cn")
local Types = require("luau/ui/types")

local Tag = SolidLuau.ui.Tag

type Reactive<T> = Types.Reactive<T>
type UINode = Types.UINode

export type CheckboxProps = {
  checked: Reactive<boolean>,
  onChange: (nextChecked: boolean) -> (),
  class: any?,
  [string]: any,
}

local function read_checked(v: Reactive<boolean>): boolean
  if type(v) == "function" then
    return v()
  end
  return v
end

local function Checkbox(props: CheckboxProps): UINode
  local checked = props.checked
  local onChange = props.onChange

  local button_props = cn.props_omit(
    props,
    { checked = true, onChange = true },
    "w-6 h-6 border border-slate-400 flex items-center justify-center cursor-pointer select-none"
  )

  button_props.children = function()
    return if read_checked(checked) then "X" else ""
  end

  button_props.onClick = function()
    onChange(not read_checked(checked))
  end

  return Tag.button(button_props)
end

return Checkbox

