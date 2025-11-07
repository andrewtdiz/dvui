class Color {
  constructor(r, g, b, a = 0xff) {
    this.value = Color.pack(r, g, b, a);
  }

  static pack(r, g, b, a = 0xff) {
    const r8 = Color.toByte(r);
    const g8 = Color.toByte(g);
    const b8 = Color.toByte(b);
    const a8 = Color.toByte(a);
    return ((r8 << 24) | (g8 << 16) | (b8 << 8) | a8) >>> 0;
  }

  static toByte(value) {
    const clamped = Math.min(255, Math.max(0, Math.round(value))); 
    return clamped >>> 0;
  }
}

const WHITE = new Color(255, 255, 255, 255);
const RED = new Color(255, 0, 0, 255);
const GREEN = new Color(0, 255, 0, 255);
const BLUE = new Color(0, 0, 255, 255);
const YELLOW = new Color(255, 255, 0, 255);
const CYAN = new Color(32, 155, 255, 255);
const MAGENTA = new Color(255, 0, 255, 255);
const BLACK = new Color(0, 0, 0, 255);
const GRAY = new Color(128, 128, 128, 255);
const BROWN = new Color(165, 42, 42, 255);

const defaultBorderColor = MAGENTA;
const pressedBorderColor = RED;

function setBorderColor(color) {
  engine.setSelectionBorderColor(color.value);
}

let totalTime = 0;

setBorderColor(defaultBorderColor);

editor.Tick.Connect(({ position, dt }) => {
  totalTime += dt;
  const newPosition = position + Math.sin(totalTime * 2.5);

  engine.setAnimatedPosition(newPosition);

  const fps = dt > 0 ? 1 / dt : 0;
});

window.addEventListener("keydown", (event) => {
  if (event.type === "keydown") {
    console.log(`keydown: ${event.code}`);
  }
});

window.addEventListener("mousedown", (event) => {
  if (event.type === "mousedown") {
    console.log(`${event.button} mouse down at ${event.x},${event.y}`);
    setBorderColor(pressedBorderColor);
  }
});

window.addEventListener("mouseup", (event) => {
  if (event.type === "mouseup") {
    console.log(`${event.button} mouse up at ${event.x},${event.y}`);
    setBorderColor(defaultBorderColor);
  }
});
