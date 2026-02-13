local SolidLuau = require("solidluau")

return function(app_module_id)
  local App = require(app_module_id)
  local host_ui = ui

  SolidLuau.ui.setAdapter(SolidLuau.ui.adapters.compat_ui(host_ui))

  function init()
    SolidLuau.ui.init(App)
  end

  function update(dt, input)
    SolidLuau.animation.step(dt)
  end

  function on_event(kind, id, payload)
    SolidLuau.ui.dispatch_event(kind, id, payload)
  end
end
