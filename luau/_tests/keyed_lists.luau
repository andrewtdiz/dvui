local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local For = SolidLuau.ui.For

local createSignal = SolidLuau.createSignal

local Testkit = require("luau/_tests/testkit")

local function assert_list(env, parent_id, expected)
  local got = env.getDirectTextValues(env.ui, parent_id)
  env.assertEq(#got, #expected, "list length")
  for i = 1, #expected do
    env.assertEq(got[i], expected[i], "list item " .. tostring(i))
  end
end

local function list_app(items)
  return function()
    return Tag.div({}) {
      For({
        each = items,
        key = function(item)
          return item
        end,
        children = function(item)
          return item
        end,
      }),
    }
  end
end

local function assert_ids_preserved(env, before, after, keys)
  for i = 1, #keys do
    local k = keys[i]
    env.assertEq(after[k], before[k], "id preserved for " .. tostring(k))
  end
end

local function assert_no_destroy_of_ids(env, ids)
  local destroyed = {}
  local log = env.ui.getLog()
  for i = 1, #log do
    local entry = log[i]
    if entry.op == "DESTROY" then
      destroyed[entry.id] = true
    end
  end
  for _, id in pairs(ids) do
    env.assertTrue(not destroyed[id], "unexpected destroy id " .. tostring(id))
  end
end

local function test_add_head()
  local env = Testkit.newEnv()
  local items, setItems = createSignal({ "A", "B", "C" })
  env.renderer.init(list_app(items))
  env.tick()
  env.ui.clearLog()

  local root_id = env.getSingleRootChildId(env.ui)
  local ids_before = env.getDirectTextIdsByValue(env.ui, root_id)

  setItems({ "X", "A", "B", "C" })
  env.tick()

  local ids_after = env.getDirectTextIdsByValue(env.ui, root_id)
  assert_ids_preserved(env, ids_before, ids_after, { "A", "B", "C" })
  assert_no_destroy_of_ids(env, ids_before)

  local creates = env.filterLog(env.ui.getLog(), "CREATE")
  local destroys = env.filterLog(env.ui.getLog(), "DESTROY")
  local moves = env.filterLog(env.ui.getLog(), "MOVE")
  env.assertEq(#creates, 1, "create count")
  env.assertEq(#destroys, 0, "destroy count")
  env.assertTrue(#moves > 0, "expected moves")

  assert_list(env, root_id, { "X", "A", "B", "C" })
end

local function test_add_middle()
  local env = Testkit.newEnv()
  local items, setItems = createSignal({ "A", "B", "C" })
  env.renderer.init(list_app(items))
  env.tick()
  env.ui.clearLog()

  local root_id = env.getSingleRootChildId(env.ui)
  local ids_before = env.getDirectTextIdsByValue(env.ui, root_id)

  setItems({ "A", "X", "B", "C" })
  env.tick()

  local ids_after = env.getDirectTextIdsByValue(env.ui, root_id)
  assert_ids_preserved(env, ids_before, ids_after, { "A", "B", "C" })
  assert_no_destroy_of_ids(env, ids_before)

  local creates = env.filterLog(env.ui.getLog(), "CREATE")
  local destroys = env.filterLog(env.ui.getLog(), "DESTROY")
  local moves = env.filterLog(env.ui.getLog(), "MOVE")
  env.assertEq(#creates, 1, "create count")
  env.assertEq(#destroys, 0, "destroy count")
  env.assertTrue(#moves > 0, "expected moves")

  assert_list(env, root_id, { "A", "X", "B", "C" })
end

local function test_add_tail()
  local env = Testkit.newEnv()
  local items, setItems = createSignal({ "A", "B", "C" })
  env.renderer.init(list_app(items))
  env.tick()
  env.ui.clearLog()

  local root_id = env.getSingleRootChildId(env.ui)
  local ids_before = env.getDirectTextIdsByValue(env.ui, root_id)

  setItems({ "A", "B", "C", "X" })
  env.tick()

  local ids_after = env.getDirectTextIdsByValue(env.ui, root_id)
  assert_ids_preserved(env, ids_before, ids_after, { "A", "B", "C" })
  assert_no_destroy_of_ids(env, ids_before)

  local creates = env.filterLog(env.ui.getLog(), "CREATE")
  local destroys = env.filterLog(env.ui.getLog(), "DESTROY")
  local moves = env.filterLog(env.ui.getLog(), "MOVE")
  env.assertEq(#creates, 1, "create count")
  env.assertEq(#destroys, 0, "destroy count")
  env.assertEq(#moves, 0, "move count")

  assert_list(env, root_id, { "A", "B", "C", "X" })
end

local function test_remove_head()
  local env = Testkit.newEnv()
  local items, setItems = createSignal({ "A", "B", "C" })
  env.renderer.init(list_app(items))
  env.tick()
  env.ui.clearLog()

  local root_id = env.getSingleRootChildId(env.ui)
  local ids_before = env.getDirectTextIdsByValue(env.ui, root_id)

  setItems({ "B", "C" })
  env.tick()

  local ids_after = env.getDirectTextIdsByValue(env.ui, root_id)
  assert_ids_preserved(env, ids_before, ids_after, { "B", "C" })

  local creates = env.filterLog(env.ui.getLog(), "CREATE")
  local destroys = env.filterLog(env.ui.getLog(), "DESTROY")
  local moves = env.filterLog(env.ui.getLog(), "MOVE")
  env.assertEq(#creates, 0, "create count")
  env.assertEq(#destroys, 1, "destroy count")
  env.assertEq(destroys[1].id, ids_before.A, "destroyed id")
  env.assertEq(#moves, 0, "move count")

  assert_list(env, root_id, { "B", "C" })
end

local function test_remove_middle()
  local env = Testkit.newEnv()
  local items, setItems = createSignal({ "A", "B", "C" })
  env.renderer.init(list_app(items))
  env.tick()
  env.ui.clearLog()

  local root_id = env.getSingleRootChildId(env.ui)
  local ids_before = env.getDirectTextIdsByValue(env.ui, root_id)

  setItems({ "A", "C" })
  env.tick()

  local ids_after = env.getDirectTextIdsByValue(env.ui, root_id)
  assert_ids_preserved(env, ids_before, ids_after, { "A", "C" })

  local creates = env.filterLog(env.ui.getLog(), "CREATE")
  local destroys = env.filterLog(env.ui.getLog(), "DESTROY")
  local moves = env.filterLog(env.ui.getLog(), "MOVE")
  env.assertEq(#creates, 0, "create count")
  env.assertEq(#destroys, 1, "destroy count")
  env.assertEq(destroys[1].id, ids_before.B, "destroyed id")
  env.assertEq(#moves, 0, "move count")

  assert_list(env, root_id, { "A", "C" })
end

local function test_remove_tail()
  local env = Testkit.newEnv()
  local items, setItems = createSignal({ "A", "B", "C" })
  env.renderer.init(list_app(items))
  env.tick()
  env.ui.clearLog()

  local root_id = env.getSingleRootChildId(env.ui)
  local ids_before = env.getDirectTextIdsByValue(env.ui, root_id)

  setItems({ "A", "B" })
  env.tick()

  local ids_after = env.getDirectTextIdsByValue(env.ui, root_id)
  assert_ids_preserved(env, ids_before, ids_after, { "A", "B" })

  local creates = env.filterLog(env.ui.getLog(), "CREATE")
  local destroys = env.filterLog(env.ui.getLog(), "DESTROY")
  local moves = env.filterLog(env.ui.getLog(), "MOVE")
  env.assertEq(#creates, 0, "create count")
  env.assertEq(#destroys, 1, "destroy count")
  env.assertEq(destroys[1].id, ids_before.C, "destroyed id")
  env.assertEq(#moves, 0, "move count")

  assert_list(env, root_id, { "A", "B" })
end

local function test_reorder_reverse()
  local env = Testkit.newEnv()
  local items, setItems = createSignal({ "A", "B", "C", "D", "E" })
  env.renderer.init(list_app(items))
  env.tick()
  env.ui.clearLog()

  local root_id = env.getSingleRootChildId(env.ui)
  local ids_before = env.getDirectTextIdsByValue(env.ui, root_id)

  setItems({ "E", "D", "C", "B", "A" })
  env.tick()

  local ids_after = env.getDirectTextIdsByValue(env.ui, root_id)
  assert_ids_preserved(env, ids_before, ids_after, { "A", "B", "C", "D", "E" })

  local creates = env.filterLog(env.ui.getLog(), "CREATE")
  local destroys = env.filterLog(env.ui.getLog(), "DESTROY")
  local moves = env.filterLog(env.ui.getLog(), "MOVE")
  env.assertEq(#creates, 0, "create count")
  env.assertEq(#destroys, 0, "destroy count")
  env.assertEq(#moves, 5, "move count")

  local moved = {}
  for i = 1, #moves do
    moved[moves[i].id] = true
  end
  for _, id in pairs(ids_before) do
    env.assertTrue(moved[id] == true, "missing move id " .. tostring(id))
  end

  assert_list(env, root_id, { "E", "D", "C", "B", "A" })
end

Testkit.run("keyed_lists.add_head", test_add_head)
Testkit.run("keyed_lists.add_middle", test_add_middle)
Testkit.run("keyed_lists.add_tail", test_add_tail)
Testkit.run("keyed_lists.remove_head", test_remove_head)
Testkit.run("keyed_lists.remove_middle", test_remove_middle)
Testkit.run("keyed_lists.remove_tail", test_remove_tail)
Testkit.run("keyed_lists.reorder_reverse", test_reorder_reverse)

return {}
