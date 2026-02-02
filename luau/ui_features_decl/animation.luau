local reactivity = require("luau/ui_features_decl/reactivity")
local easing = require("luau/ui_features_decl/easing")

local createSignal = reactivity.createSignal
local createEffect = reactivity.createEffect
local onCleanup = reactivity.onCleanup
local batch = reactivity.batch

local UPDATE_RATE = 120
local UPDATE_STEP = 1 / UPDATE_RATE
local MAX_SUBSTEPS = 16

local active_springs = {}
local active_tweens = {}

local spring_accumulator = 0

local function clamp(v, min_value, max_value)
  if v < min_value then
    return min_value
  end
  if v > max_value then
    return max_value
  end
  return v
end

local function is_number_array(v)
  if type(v) ~= "table" then
    return false
  end
  local len = #v
  if len <= 0 then
    return false
  end
  for i = 1, len do
    if type(v[i]) ~= "number" then
      return false
    end
  end
  return true
end

local function shape_from_value(v)
  if type(v) == "number" then
    return "number", 1
  end
  if is_number_array(v) then
    return "array", #v
  end
  error("animation value must be number or {number}", 0)
end

local function normalize_value(kind, len, v)
  if kind == "number" then
    if type(v) ~= "number" then
      error("animation value expected number", 0)
    end
    return v
  end

  if type(v) ~= "table" or #v ~= len then
    error("animation value array length changed", 0)
  end
  local out = {}
  for i = 1, len do
    local n = v[i]
    if type(n) ~= "number" then
      error("animation value array element must be number", 0)
    end
    out[i] = n
  end
  return out
end

local function vec_from_normalized(kind, len, v)
  if kind == "number" then
    return { v }
  end
  local out = {}
  for i = 1, len do
    out[i] = v[i]
  end
  return out
end

local function vec_zero(len)
  local out = {}
  for i = 1, len do
    out[i] = 0
  end
  return out
end

local function vec_clone(vec, len)
  local out = {}
  for i = 1, len do
    out[i] = vec[i]
  end
  return out
end

local function vec_max_abs(vec, len)
  local m = 0
  for i = 1, len do
    local a = math.abs(vec[i])
    if a > m then
      m = a
    end
  end
  return m
end

local function vec_max_abs_diff(a, b, len)
  local m = 0
  for i = 1, len do
    local d = math.abs(a[i] - b[i])
    if d > m then
      m = d
    end
  end
  return m
end

local function value_from_vec(kind, len, vec)
  if kind == "number" then
    return vec[1]
  end
  local out = {}
  for i = 1, len do
    out[i] = vec[i]
  end
  return out
end

local function createSpring(source_fn, opts)
  if type(source_fn) ~= "function" then
    error("createSpring source must be function", 0)
  end
  if opts ~= nil and type(opts) ~= "table" then
    error("createSpring options must be table", 0)
  end

  local stiffness = 100
  local damping = 10
  if opts ~= nil then
    if opts.stiffness ~= nil then
      if type(opts.stiffness) ~= "number" or opts.stiffness <= 0 then
        error("createSpring stiffness must be positive number", 0)
      end
      stiffness = opts.stiffness
    end
    if opts.damping ~= nil then
      if type(opts.damping) ~= "number" or opts.damping < 0 then
        error("createSpring damping must be non-negative number", 0)
      end
      damping = opts.damping
    end
  end

  local k = stiffness
  local c = damping

  if c > UPDATE_RATE * 2 then
    error("createSpring damping too high", 0)
  end

  local output, set_output = createSignal(nil)

  local state = {
    kind = nil,
    len = nil,
    k = k,
    c = c,
    x = nil,
    v = nil,
    goal = nil,
    source_value = nil,
    set_output = set_output,
  }

  onCleanup(function()
    active_springs[state] = nil
  end)

  createEffect(function()
    local value = source_fn()
    if state.kind == nil then
      local kind, len = shape_from_value(value)
      local normalized = normalize_value(kind, len, value)
      state.kind = kind
      state.len = len
      state.x = vec_from_normalized(kind, len, normalized)
      state.v = vec_zero(len)
      state.goal = vec_from_normalized(kind, len, normalized)
      state.source_value = normalized
      set_output(normalized)
      return
    end

    local normalized = normalize_value(state.kind, state.len, value)
    state.goal = vec_from_normalized(state.kind, state.len, normalized)
    state.source_value = normalized
    active_springs[state] = true
  end)

  local function access(...)
    if select("#", ...) == 0 then
      return output()
    end

    local value = ...
    if state.kind == nil then
      local kind, len = shape_from_value(value)
      local normalized = normalize_value(kind, len, value)
      state.kind = kind
      state.len = len
      state.x = vec_from_normalized(kind, len, normalized)
      state.v = vec_zero(len)
      state.goal = vec_from_normalized(kind, len, normalized)
      state.source_value = normalized
      set_output(normalized)
      return normalized
    end

    local normalized = normalize_value(state.kind, state.len, value)
    state.x = vec_from_normalized(state.kind, state.len, normalized)
    state.v = vec_zero(state.len)
    active_springs[state] = true
    set_output(normalized)
    return normalized
  end

  local function config(next_opts)
    if type(next_opts) ~= "table" then
      error("createSpring config must be table", 0)
    end

    if next_opts.stiffness ~= nil then
      if type(next_opts.stiffness) ~= "number" or next_opts.stiffness <= 0 then
        error("createSpring stiffness must be positive number", 0)
      end
      stiffness = next_opts.stiffness
    end

    if next_opts.damping ~= nil then
      if type(next_opts.damping) ~= "number" or next_opts.damping < 0 then
        error("createSpring damping must be non-negative number", 0)
      end
      damping = next_opts.damping
    end

    state.k = stiffness
    state.c = damping

    local position = next_opts.position
    local velocity = next_opts.velocity
    local impulse = next_opts.impulse

    if position ~= nil and state.kind == nil then
      local kind, len = shape_from_value(position)
      state.kind = kind
      state.len = len
      state.x = vec_from_normalized(kind, len, normalize_value(kind, len, position))
      state.v = vec_zero(len)
      state.goal = vec_clone(state.x, len)
      state.source_value = normalize_value(kind, len, position)
      set_output(state.source_value)
    end

    if state.kind == nil then
      error("createSpring config called before initialization", 0)
    end

    if position ~= nil then
      local normalized = normalize_value(state.kind, state.len, position)
      state.x = vec_from_normalized(state.kind, state.len, normalized)
      set_output(normalized)
    end

    if velocity ~= nil then
      local normalized = normalize_value(state.kind, state.len, velocity)
      state.v = vec_from_normalized(state.kind, state.len, normalized)
    end

    if impulse ~= nil then
      local impulse_vec = vec_from_normalized(state.kind, state.len, normalize_value(state.kind, state.len, impulse))
      for i = 1, state.len do
        state.v[i] = state.v[i] + impulse_vec[i]
      end
    end

    active_springs[state] = true
  end

  return access, config
end

local function createTween(source_fn, opts)
  if type(source_fn) ~= "function" then
    error("createTween source must be function", 0)
  end
  if opts ~= nil and type(opts) ~= "table" then
    error("createTween options must be table", 0)
  end

  local duration = 0.3
  local easing_fn = easing.linear
  if opts ~= nil then
    if opts.duration ~= nil then
      if type(opts.duration) ~= "number" or opts.duration <= 0 then
        error("createTween duration must be positive number", 0)
      end
      duration = opts.duration
    end
    if opts.easing ~= nil then
      if type(opts.easing) ~= "function" then
        error("createTween easing must be function", 0)
      end
      easing_fn = opts.easing
    end
  end

  local output, set_output = createSignal(nil)

  local state = {
    kind = nil,
    len = nil,
    elapsed = 0,
    duration = duration,
    easing = easing_fn,
    from = nil,
    to = nil,
    current = nil,
    target_value = nil,
    set_output = set_output,
  }

  onCleanup(function()
    active_tweens[state] = nil
  end)

  createEffect(function()
    local value = source_fn()
    if state.kind == nil then
      local kind, len = shape_from_value(value)
      local normalized = normalize_value(kind, len, value)
      state.kind = kind
      state.len = len
      state.current = vec_from_normalized(kind, len, normalized)
      state.from = vec_clone(state.current, len)
      state.to = vec_clone(state.current, len)
      state.elapsed = state.duration
      state.target_value = normalized
      set_output(normalized)
      return
    end

    local normalized = normalize_value(state.kind, state.len, value)
    state.from = vec_clone(state.current, state.len)
    state.to = vec_from_normalized(state.kind, state.len, normalized)
    state.elapsed = 0
    state.target_value = normalized
    active_tweens[state] = true
  end)

  local function access(...)
    if select("#", ...) == 0 then
      return output()
    end

    local value = ...
    if state.kind == nil then
      local kind, len = shape_from_value(value)
      local normalized = normalize_value(kind, len, value)
      state.kind = kind
      state.len = len
      state.current = vec_from_normalized(kind, len, normalized)
      state.from = vec_clone(state.current, len)
      state.to = vec_clone(state.current, len)
      state.elapsed = state.duration
      state.target_value = normalized
      set_output(normalized)
      return normalized
    end

    local normalized = normalize_value(state.kind, state.len, value)
    state.current = vec_from_normalized(state.kind, state.len, normalized)
    state.from = vec_clone(state.current, state.len)
    state.to = vec_clone(state.current, state.len)
    state.elapsed = state.duration
    state.target_value = normalized
    active_tweens[state] = nil
    set_output(normalized)
    return normalized
  end

  local function config(next_opts)
    if type(next_opts) ~= "table" then
      error("createTween config must be table", 0)
    end

    local new_duration = next_opts.duration
    if new_duration ~= nil then
      if type(new_duration) ~= "number" or new_duration <= 0 then
        error("createTween duration must be positive number", 0)
      end
      state.duration = new_duration
    end

    local new_easing = next_opts.easing
    if new_easing ~= nil then
      if type(new_easing) ~= "function" then
        error("createTween easing must be function", 0)
      end
      state.easing = new_easing
    end

    local position = next_opts.position
    if position ~= nil then
      access(position)
    end
  end

  return access, config
end

local function step(dt)
  if type(dt) ~= "number" or dt <= 0 then
    return
  end

  spring_accumulator = spring_accumulator + dt

  local steps = 0
  while spring_accumulator > UPDATE_STEP and steps < MAX_SUBSTEPS do
    spring_accumulator = spring_accumulator - UPDATE_STEP
    steps = steps + 1

    for state in pairs(active_springs) do
      local len = state.len
      if len ~= nil then
        local k = state.k
        local c = state.c
        local x = state.x
        local v = state.v
        local goal = state.goal
        for i = 1, len do
          local dx = x[i] - goal[i]
          local a = (-k * dx) + (-c * v[i])
          local next_v = v[i] + a * UPDATE_STEP
          v[i] = next_v
          x[i] = x[i] + next_v * UPDATE_STEP
        end
      end
    end
  end

  if steps == MAX_SUBSTEPS then
    spring_accumulator = 0
  end

  batch(function()
    if steps > 0 then
      local remove_springs = {}
      for state in pairs(active_springs) do
        local len = state.len
        local kind = state.kind
        local x = state.x
        local v = state.v
        local goal = state.goal

        local max_goal = vec_max_abs(goal, len)
        local eps = math.max(1e-6, max_goal * 1e-4)

        local pos_err = vec_max_abs_diff(x, goal, len)
        local vel_err = vec_max_abs(v, len)

        if pos_err <= eps and vel_err <= eps then
          remove_springs[#remove_springs + 1] = state
          state.x = vec_clone(goal, len)
          state.v = vec_zero(len)
          state.set_output(state.source_value)
        else
          state.set_output(value_from_vec(kind, len, x))
        end
      end
      for _, state in ipairs(remove_springs) do
        active_springs[state] = nil
      end
    end

    local remove_tweens = {}
    for state in pairs(active_tweens) do
      local len = state.len
      if len ~= nil then
        local elapsed = state.elapsed + dt
        state.elapsed = elapsed

        local t = clamp(elapsed / state.duration, 0, 1)
        local p = state.easing(t)

        local from = state.from
        local to = state.to
        local current = state.current

        for i = 1, len do
          current[i] = from[i] + (to[i] - from[i]) * p
        end

        if t == 1 then
          remove_tweens[#remove_tweens + 1] = state
          local target_value = state.target_value
          state.current = vec_from_normalized(state.kind, len, target_value)
          state.set_output(target_value)
        else
          state.set_output(value_from_vec(state.kind, len, current))
        end
      end
    end
    for _, state in ipairs(remove_tweens) do
      active_tweens[state] = nil
    end
  end)
end

return {
  easing = easing,
  createSpring = createSpring,
  step = step,
  createTween = createTween,
}
