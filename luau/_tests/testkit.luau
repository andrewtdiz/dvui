local SolidLuau = require("solidluau")
local Scheduler = require("core/scheduler")
local MockUi = require("luau/_tests/mock_ui")
local TestScheduler = require("luau/_tests/test_scheduler")

local function fail(msg)
  error(msg or "assert", 0)
end

local function assertTrue(v, msg)
  if v then
    return
  end
  fail(msg)
end

local function assertEq(a, b, msg)
  if a == b then
    return
  end
  fail((msg or "assertEq") .. " expected=" .. tostring(b) .. " got=" .. tostring(a))
end

local function deepEqual(a, b)
  if a == b then
    return true
  end
  local ta = type(a)
  if ta ~= type(b) then
    return false
  end
  if ta ~= "table" then
    return false
  end

  local a_len = #a
  local b_len = #b
  if a_len ~= b_len then
    return false
  end
  for i = 1, a_len do
    if not deepEqual(a[i], b[i]) then
      return false
    end
  end

  local seen = {}
  for k, v in pairs(a) do
    if type(k) == "number" and k >= 1 and k <= a_len and k == math.floor(k) then
      continue
    end
    if not deepEqual(v, b[k]) then
      return false
    end
    seen[k] = true
  end

  for k in pairs(b) do
    if type(k) == "number" and k >= 1 and k <= b_len and k == math.floor(k) then
      continue
    end
    if not seen[k] then
      return false
    end
  end

  return true
end

local function collectSubtreeIds(ui, root_id)
  local out = {}

  local function walk(id)
    out[id] = true
    local node = ui.getNode(id)
    if node == nil then
      return
    end
    local children = node.children
    if type(children) ~= "table" then
      return
    end
    for i = 1, #children do
      walk(children[i])
    end
  end

  walk(root_id)
  return out
end

local function getSingleRootChildId(ui)
  local root = ui.getNode(0)
  assertTrue(root ~= nil, "missing root")
  local children = root.children
  assertTrue(type(children) == "table", "root children missing")
  assertEq(#children, 1, "root child count")
  return children[1]
end

local function getDirectTextValues(ui, parent_id)
  local parent = ui.getNode(parent_id)
  assertTrue(parent ~= nil, "missing parent")
  local out = {}
  for i = 1, #parent.children do
    local child_id = parent.children[i]
    local child = ui.getNode(child_id)
    if child ~= nil and child.tag == "text" then
      out[#out + 1] = child.props.Text or ""
    end
  end
  return out
end

local function getDirectTextIdsByValue(ui, parent_id)
  local parent = ui.getNode(parent_id)
  assertTrue(parent ~= nil, "missing parent")
  local out = {}
  for i = 1, #parent.children do
    local child_id = parent.children[i]
    local child = ui.getNode(child_id)
    if child ~= nil and child.tag == "text" then
      local text = child.props.Text or ""
      assertTrue(out[text] == nil, "duplicate text value " .. text)
      out[text] = child_id
    end
  end
  return out
end

local function filterLog(log, op)
  local out = {}
  for i = 1, #log do
    local entry = log[i]
    if entry.op == op then
      out[#out + 1] = entry
    end
  end
  return out
end

local function newEnv()
  local scheduler = TestScheduler.newTestScheduler()
  Scheduler.setScheduler(scheduler)

  local ui = MockUi.newMockUi()
  local renderer = SolidLuau.ui.createRenderer(SolidLuau.ui.adapters.compat_ui(ui))

  return {
    ui = ui,
    renderer = renderer,
    scheduler = scheduler,
    tick = scheduler.tick,
    assertTrue = assertTrue,
    assertEq = assertEq,
    deepEqual = deepEqual,
    collectSubtreeIds = collectSubtreeIds,
    getSingleRootChildId = getSingleRootChildId,
    getDirectTextValues = getDirectTextValues,
    getDirectTextIdsByValue = getDirectTextIdsByValue,
    filterLog = filterLog,
  }
end

return {
  newEnv = newEnv,
}

