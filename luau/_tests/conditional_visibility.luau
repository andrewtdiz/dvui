local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local Show = SolidLuau.ui.Show

local createSignal = SolidLuau.createSignal

local Testkit = require("luau/_tests/testkit")

local function app(visible)
  return function()
    return Tag.div({}) {
      Show({
        when = visible,
        children = function()
          return Tag.div({ class = "panel" }) {
            "Hello",
            Tag.div({}) { "Nested" },
          }
        end,
      }),
    }
  end
end

local function first_non_slot_child(ui, parent_id)
  local parent = ui.getNode(parent_id)
  if parent == nil then
    return nil
  end
  for i = 1, #parent.children do
    local child = ui.getNode(parent.children[i])
    if child ~= nil and child.tag ~= "slot" then
      return child.id
    end
  end
  return nil
end

local function expected_panel_snapshot()
  return {
    tag = "div",
    class = "panel",
    children = {
      { tag = "text", text = "Hello", children = {} },
      {
        tag = "div",
        children = {
          { tag = "text", text = "Nested", children = {} },
        },
      },
    },
  }
end

local function test_toggle_off_on()
  local env = Testkit.newEnv()
  local visible, setVisible = createSignal(true)
  env.renderer.init(app(visible))
  env.tick()
  env.ui.clearLog()

  local root_id = env.getSingleRootChildId(env.ui)
  local branch_id = first_non_slot_child(env.ui, root_id)
  env.assertTrue(branch_id ~= nil, "missing branch")

  local expected = expected_panel_snapshot()
  env.assertTrue(env.deepEqual(env.ui.snapshotLite(branch_id), expected), "initial subtree mismatch")

  local subtree_ids = env.collectSubtreeIds(env.ui, branch_id)

  setVisible(false)
  env.tick()

  local destroyed = {}
  local log = env.ui.getLog()
  for i = 1, #log do
    local entry = log[i]
    if entry.op == "DESTROY" then
      destroyed[entry.id] = true
    end
  end

  for id in pairs(subtree_ids) do
    env.assertTrue(destroyed[id] == true, "missing destroy id " .. tostring(id))
    env.assertTrue(not env.ui.exists(id), "id still exists " .. tostring(id))
  end

  local parent = env.ui.getNode(root_id)
  local non_slot = first_non_slot_child(env.ui, root_id)
  env.assertTrue(non_slot == nil, "expected no branch children")
  env.assertTrue(parent ~= nil and #parent.children == 1, "expected only slot child")

  env.ui.clearLog()
  setVisible(true)
  env.tick()

  local new_branch_id = first_non_slot_child(env.ui, root_id)
  env.assertTrue(new_branch_id ~= nil, "missing new branch")
  env.assertTrue(env.deepEqual(env.ui.snapshotLite(new_branch_id), expected), "remount subtree mismatch")

  local new_subtree_ids = env.collectSubtreeIds(env.ui, new_branch_id)
  for id in pairs(new_subtree_ids) do
    env.assertTrue(subtree_ids[id] ~= true, "reused id " .. tostring(id))
  end
end

local function test_toggle_off_on_same_frame()
  local env = Testkit.newEnv()
  local visible, setVisible = createSignal(true)
  env.renderer.init(app(visible))
  env.tick()
  env.ui.clearLog()

  local root_id = env.getSingleRootChildId(env.ui)
  local before_snapshot = env.ui.snapshotLite(root_id)

  setVisible(false)
  setVisible(true)
  env.tick()

  env.assertEq(#env.ui.getLog(), 0, "expected no ops")
  local after_snapshot = env.ui.snapshotLite(root_id)
  env.assertTrue(env.deepEqual(before_snapshot, after_snapshot), "tree changed")
end

test_toggle_off_on()
test_toggle_off_on_same_frame()

return {}

