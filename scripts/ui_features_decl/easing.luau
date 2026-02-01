local function linear(t)
  return t
end

local function inQuad(t)
  return t * t
end

local function outQuad(t)
  return 1 - inQuad(1 - t)
end

local function inOutQuad(t)
  if t < 0.5 then
    return inQuad(t * 2) / 2
  end
  return 1 - inQuad((1 - t) * 2) / 2
end

local function inCubic(t)
  return t * t * t
end

local function outCubic(t)
  return 1 - inCubic(1 - t)
end

local function inOutCubic(t)
  if t < 0.5 then
    return inCubic(t * 2) / 2
  end
  return 1 - inCubic((1 - t) * 2) / 2
end

local function inQuart(t)
  return t * t * t * t
end

local function outQuart(t)
  return 1 - inQuart(1 - t)
end

local function inOutQuart(t)
  if t < 0.5 then
    return inQuart(t * 2) / 2
  end
  return 1 - inQuart((1 - t) * 2) / 2
end

local function inQuint(t)
  return t * t * t * t * t
end

local function outQuint(t)
  return 1 - inQuint(1 - t)
end

local function inOutQuint(t)
  if t < 0.5 then
    return inQuint(t * 2) / 2
  end
  return 1 - inQuint((1 - t) * 2) / 2
end

local function inSine(t)
  return 1 - math.cos(t * math.pi / 2)
end

local function outSine(t)
  return math.sin(t * math.pi / 2)
end

local function inOutSine(t)
  return (math.cos(t * math.pi) - 1) / -2
end

local function inExpo(t)
  return 2 ^ (10 * (t - 1))
end

local function outExpo(t)
  return 1 - inExpo(1 - t)
end

local function inOutExpo(t)
  if t < 0.5 then
    return inExpo(t * 2) / 2
  end
  return 1 - inExpo((1 - t) * 2) / 2
end

local function inCirc(t)
  return -(math.sqrt(1 - t * t) - 1)
end

local function outCirc(t)
  return 1 - inCirc(1 - t)
end

local function inOutCirc(t)
  if t < 0.5 then
    return inCirc(t * 2) / 2
  end
  return 1 - inCirc((1 - t) * 2) / 2
end

local function outElastic(t)
  local p = 0.3
  return (2 ^ (-10 * t)) * math.sin((t - p / 4) * (2 * math.pi) / p) + 1
end

local function inElastic(t)
  return 1 - outElastic(1 - t)
end

local function inOutElastic(t)
  if t < 0.5 then
    return inElastic(t * 2) / 2
  end
  return 1 - inElastic((1 - t) * 2) / 2
end

local function inBack(t)
  local s = 1.70158
  return t * t * ((s + 1) * t - s)
end

local function outBack(t)
  return 1 - inBack(1 - t)
end

local function inOutBack(t)
  if t < 0.5 then
    return inBack(t * 2) / 2
  end
  return 1 - inBack((1 - t) * 2) / 2
end

local function outBounce(t)
  local div = 2.75
  local mult = 7.5625

  if t < 1 / div then
    return mult * t * t
  end
  if t < 2 / div then
    local x = t - 1.5 / div
    return mult * x * x + 0.75
  end
  if t < 2.5 / div then
    local x = t - 2.25 / div
    return mult * x * x + 0.9375
  end
  local x = t - 2.625 / div
  return mult * x * x + 0.984375
end

local function inBounce(t)
  return 1 - outBounce(1 - t)
end

local function inOutBounce(t)
  if t < 0.5 then
    return inBounce(t * 2) / 2
  end
  return 1 - inBounce((1 - t) * 2) / 2
end

return {
  linear = linear,

  inQuad = inQuad,
  outQuad = outQuad,
  inOutQuad = inOutQuad,

  inCubic = inCubic,
  outCubic = outCubic,
  inOutCubic = inOutCubic,

  inQuart = inQuart,
  outQuart = outQuart,
  inOutQuart = inOutQuart,

  inQuint = inQuint,
  outQuint = outQuint,
  inOutQuint = inOutQuint,

  inSine = inSine,
  outSine = outSine,
  inOutSine = inOutSine,

  inExpo = inExpo,
  outExpo = outExpo,
  inOutExpo = inOutExpo,

  inCirc = inCirc,
  outCirc = outCirc,
  inOutCirc = inOutCirc,

  inElastic = inElastic,
  outElastic = outElastic,
  inOutElastic = inOutElastic,

  inBack = inBack,
  outBack = outBack,
  inOutBack = inOutBack,

  inBounce = inBounce,
  outBounce = outBounce,
  inOutBounce = inOutBounce,
}
