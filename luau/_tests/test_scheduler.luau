local function newTestScheduler()
  local queue = {}
  local head = 1
  local tail = 0

  local function schedule(task)
    tail = tail + 1
    queue[tail] = task
  end

  local function clear()
    table.clear(queue)
    head = 1
    tail = 0
  end

  local function tick()
    local steps = 0
    while head <= tail do
      steps = steps + 1
      if steps > 10000 then
        error("scheduler overflow", 0)
      end

      local task = queue[head]
      queue[head] = nil
      head = head + 1

      if task ~= nil then
        task()
      end
    end
    head = 1
    tail = 0
  end

  return {
    schedule = schedule,
    clear = clear,
    tick = tick,
  }
end

return {
  newTestScheduler = newTestScheduler,
}

