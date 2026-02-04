local SolidLuau = require("solidluau")
local cn = require("luau/ui/cn")
local Types = require("luau/ui/types")

local Tag = SolidLuau.ui.Tag
local animation = SolidLuau.animation

local div = Tag.div
local p = Tag.p

type Reactive<T> = Types.Reactive<T>

export type BarBaseProps = {
  class: any?,
  children: any?,
  [string]: any,
}

export type BarFillProps = BarBaseProps & {
  percent: Reactive<number>?,
  tween: boolean?,
  duration: number?,
  easing: ((t: number) -> number)?,
}

export type BarLabelProps = BarBaseProps & {
  current: Reactive<number | string>?,
  max: Reactive<number | string>?,
}

local function clamp_percent(v: any): number
  local n = tonumber(v)
  if n == nil then
    return 0
  end
  if n < 0 then
    return 0
  end
  if n > 100 then
    return 100
  end
  return n
end

local function BarTrack(spec: BarBaseProps?): any
  return div(cn.props(spec, "relative h-4 w-48 rounded-full bg-slate-800"))
end

local function BarRoot(spec: BarBaseProps?): any
  return div(cn.props(spec, "relative"))
end

local function BarFill(spec: BarFillProps?): any
  local percent = if spec and spec.percent ~= nil then spec.percent else 100

  local tween = true
  local duration = 0.3
  local easing = animation.easing.outCubic
  if spec ~= nil then
    if spec.tween ~= nil then
      tween = spec.tween
    end
    if spec.duration ~= nil then
      duration = spec.duration
    end
    if spec.easing ~= nil then
      easing = spec.easing
    end
  end

  local function scale_value()
    local percent_value: number
    if type(percent) == "function" then
      percent_value = percent()
    else
      percent_value = percent
    end
    return clamp_percent(percent_value) / 100
  end

  local scaleX = scale_value
  if tween ~= false then
    scaleX = animation.createTween(scale_value, { duration = duration, easing = easing })
  end

  local props = cn.props_omit(
    spec,
    {
      percent = true,
      tween = true,
      duration = true,
      easing = true,
    },
    "h-full w-full transition-all duration-300"
  )

  if props.transform == nil then
    props.transform = {
      scaleX = scaleX,
      anchorX = 0,
      anchorY = 0,
    }
  end
  return div(props)
end

local function BarLabel(spec: BarLabelProps?): any
  local current = if spec then spec.current else nil
  local max = if spec then spec.max else nil

  local props = cn.props_omit(spec, { current = true, max = true }, "absolute left-[50%] top-[50%] anchor-center")

  if props.children == nil and (current ~= nil or max ~= nil) then
    props.children = function()
      return string.format("%s/%s", tostring(if type(current) == "function" then current() else current), tostring(if type(max) == "function" then max() else max))
    end
  end

  return p(props)
end

local Bar = {
  Root = BarRoot,
  Track = BarTrack,
  Fill = BarFill,
  Label = BarLabel,
}

Bar.BarRoot = BarRoot
Bar.BarTrack = BarTrack
Bar.BarFill = BarFill
Bar.BarLabel = BarLabel

return Bar
