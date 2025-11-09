export const COLOR_PRESETS = Object.freeze({
  RED_500: 0xef4444ff,
  BLUE_500: 0x3b82f6ff,
  GREEN_500: 0x22c55eff,
  AMBER_500: 0xf59e0bff,
});

const COLOR_SUFFIXES = Object.freeze({
  "red-500": COLOR_PRESETS.RED_500,
  "blue-500": COLOR_PRESETS.BLUE_500,
  "green-500": COLOR_PRESETS.GREEN_500,
  "amber-500": COLOR_PRESETS.AMBER_500,
});

const EMPTY_STYLE = Object.freeze({});

export function parseClassNames(className, componentState = EMPTY_STYLE) {
  if (typeof className !== "string" || className.trim().length === 0) {
    return null;
  }

  const style = {};
  const tokens = className.split(/\s+/);

  for (const rawToken of tokens) {
    const token = rawToken.trim();
    if (!token) continue;

    const normalized = normalizeToken(token, componentState);
    if (normalized.startsWith("bg-")) {
      const color = resolveColor(normalized.slice(3));
      if (color != null) {
        style.backgroundColor = color;
      }
      continue;
    }

    if (normalized.startsWith("text-")) {
      const color = resolveColor(normalized.slice(5));
      if (color != null) {
        style.textColor = color;
      }
    }
  }

  return Object.keys(style).length === 0 ? null : style;
}

function normalizeToken(token, _componentState) {
  // Variant support (hover:, focus:, etc.) will plug in here later.
  const parts = token.split(":");
  return parts[parts.length - 1] ?? token;
}

function resolveColor(suffix) {
  return COLOR_SUFFIXES[suffix] ?? null;
}
