local SolidLuau = require("solidluau")
local cn = require("luau/ui/cn")
local Types = require("luau/ui/types")

local Tag = SolidLuau.ui.Tag

local button = Tag.button
local div = Tag.div

type Reactive<T> = Types.Reactive<T>
type UINode = Types.UINode

export type ToggleProps = {
  on: Reactive<boolean>,
  onChange: (nextOn: boolean) -> (),
  class: any?,
  [string]: any,
}

local function resolve_bool(v: Reactive<boolean>): boolean
  if type(v) == "function" then
    return v()
  end
  return v
end

local function Toggle(props: ToggleProps): UINode
  local function is_on()
    return resolve_bool(props.on)
  end

  local root_props = cn.props_omit(
    props,
    { on = true, onChange = true },
    "relative w-10 h-6 rounded-full border-2",
    function()
      if is_on() then
        return "bg-blue-600 border-blue-400"
      end
      return "bg-neutral-900 border-neutral-700"
    end
  )

  root_props.onClick = function()
    props.onChange(not is_on())
  end

  local knob = div({
    class = cn(
      "absolute top-[50%] anchor-center w-4 h-4 rounded-full bg-white",
      function()
        if is_on() then
          return "right-1"
        end
        return "left-1"
      end
    ),
  })

  return button(root_props){
    knob,
  }
end

return Toggle

