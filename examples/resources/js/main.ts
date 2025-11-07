let totalTime = 0;

editor.Tick.Connect(({ position, dt }: FrameArgs) => {
  totalTime += dt;
  const newPosition = position + Math.sin(totalTime * 2.5);

  const fps = dt > 0 ? 1 / dt : 0;
  std.printf(`\rdt:${dt.toFixed(4)} fps:${fps.toFixed(1)} mouse:${mouse.x},${mouse.y}`);

  return newPosition;
});

window.addEventListener("keydown", (event) => {
  if (event.type === "keydown") {
    std.printf(`\nkeydown: ${event.code}`);
  }
});

window.addEventListener("mousedown", (event) => {
  if (event.type === "mousedown") {
    std.printf(`\n${event.button} mouse down at ${event.x},${event.y}`);
  }
});
