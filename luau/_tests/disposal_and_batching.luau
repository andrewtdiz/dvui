local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local Show = SolidLuau.ui.Show

local createSignal = SolidLuau.createSignal

local Testkit = require("luau/_tests/testkit")

local function app_single_effect(mounted, value)
  return function()
    return Tag.div({}) {
      Show({
        when = mounted,
        children = function()
          return function()
            return value()
          end
        end,
      }),
    }
  end
end

local function app_nested_effects(mounted, a, b)
  return function()
    return Tag.div({}) {
      Show({
        when = mounted,
        children = function()
          return Tag.div({}) {
            function()
              return a()
            end,
            Tag.div({}) {
              function()
                return b()
              end,
            },
          }
        end,
      }),
    }
  end
end

local function test_single_effect_disposed()
  local env = Testkit.newEnv()
  local mounted, setMounted = createSignal(true)
  local value, setValue = createSignal("a")
  env.renderer.init(app_single_effect(mounted, value))
  env.tick()
  env.ui.clearLog()

  setMounted(false)
  env.tick()
  env.ui.clearLog()

  setValue("b")
  env.tick()

  env.assertEq(#env.ui.getLog(), 0, "expected no ops after dispose")
end

local function test_nested_effects_disposed()
  local env = Testkit.newEnv()
  local mounted, setMounted = createSignal(true)
  local a, setA = createSignal("a")
  local b, setB = createSignal("b")
  env.renderer.init(app_nested_effects(mounted, a, b))
  env.tick()
  env.ui.clearLog()

  setMounted(false)
  env.tick()
  env.ui.clearLog()

  setA("a2")
  setB("b2")
  env.tick()

  env.assertEq(#env.ui.getLog(), 0, "expected no ops after dispose")
end

local function test_batching_one_update()
  local env = Testkit.newEnv()
  local health, setHealth = createSignal(100)

  env.renderer.init(function()
    return function()
      return tostring(health())
    end
  end)

  env.tick()
  env.ui.clearLog()

  setHealth(90)
  setHealth(50)
  setHealth(25)
  env.tick()

  local log = env.ui.getLog()
  env.assertEq(#log, 1, "op count")
  env.assertEq(log[1].op, "UPDATE", "op kind")
  env.assertEq(log[1].props.Text, "25", "final value")
end

test_single_effect_disposed()
test_nested_effects_disposed()
test_batching_one_update()

return {}

