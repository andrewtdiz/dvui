local Checkbox = require("luau/components/checkbox")

local function assert_ok(v, msg)
  if v then
    return
  end
  error(msg or "assert", 0)
end

do
  local got = nil
  local node = Checkbox({
    checked = false,
    onChange = function(nextChecked)
      got = nextChecked
    end,
  })

  node.onClick(nil, 0, "click")
  assert_ok(got == true, "unchecked click toggles to true")
end

do
  local got = nil
  local node = Checkbox({
    checked = true,
    onChange = function(nextChecked)
      got = nextChecked
    end,
  })

  node.onClick(nil, 0, "click")
  assert_ok(got == false, "checked click toggles to false")
end

