import type { ColorInput, NodeProps } from "./node";

const toByte = (value: number) => {
  if (Number.isNaN(value) || !Number.isFinite(value)) return 0;
  if (value < 0) return 0;
  if (value > 255) return 255;
  return value | 0;
};

export const packColor = (value?: ColorInput): number => {
  if (typeof value === "number") return value >>> 0;
  if (!value) return 0xffffffff;

  if (Array.isArray(value) || value instanceof Uint8Array || value instanceof Uint8ClampedArray) {
    const r = toByte(value[0]);
    const g = toByte(value[1]);
    const b = toByte(value[2]);
    const a = toByte(value[3] ?? 255);
    return ((r << 24) | (g << 16) | (b << 8) | a) >>> 0;
  }

  const normalized = value.startsWith("#") ? value.slice(1) : value;
  const expanded =
    normalized.length === 6
      ? `${normalized}ff`
      : normalized.length === 8
      ? normalized
      : normalized.padEnd(8, "f");
  const parsed = Number.parseInt(expanded, 16);
  if (Number.isNaN(parsed)) return 0xffffffff;
  return parsed >>> 0;
};

export const frameFromProps = (props: NodeProps) => ({
  x: props.x ?? 0,
  y: props.y ?? 0,
  width: props.width ?? 0,
  height: props.height ?? 0,
});

export const transformFields = [
  "rotation",
  "scaleX",
  "scaleY",
  "anchorX",
  "anchorY",
  "translateX",
  "translateY",
] as const;

export const visualFields = ["opacity", "cornerRadius", "background", "textColor", "clipChildren"] as const;

export const hasAbsoluteClass = (props: NodeProps) => {
  const raw = props.className ?? props.class;
  if (!raw) return false;
  return raw
    .split(/\s+/)
    .map((c) => c.trim())
    .filter(Boolean)
    .includes("absolute");
};

export const bgColorFromClass = (props: NodeProps): ColorInput | undefined => {
  const raw = props.className ?? props.class;
  if (!raw) return undefined;
  const tokens = raw.split(/\s+/).filter(Boolean);

  const named: Record<string, [number, number, number]> = {
    black: [0, 0, 0],
    white: [255, 255, 255],
    "gray-900": [17, 24, 39],
    "gray-800": [31, 41, 55],
    "gray-700": [55, 65, 81],
    "gray-600": [75, 85, 99],
    "gray-500": [107, 114, 128],
    "gray-400": [156, 163, 175],
    "blue-900": [30, 58, 138],
    "blue-800": [30, 64, 175],
    "blue-700": [29, 78, 216],
    "blue-600": [37, 99, 235],
    "blue-500": [59, 130, 246],
    "blue-400": [96, 165, 250],
  };

  for (const token of tokens) {
    if (!token.startsWith("bg-")) continue;
    const name = token.slice(3);
    if (name.startsWith("[") && name.endsWith("]")) {
      const inner = name.slice(1, -1);
      const hex = inner.startsWith("#") ? inner.slice(1) : inner;
      const parsed = Number.parseInt(hex, 16);
      if (!Number.isNaN(parsed)) {
        if (hex.length === 6) {
          const r = (parsed >> 16) & 0xff;
          const g = (parsed >> 8) & 0xff;
          const b = parsed & 0xff;
          return [r, g, b, 255] as [number, number, number, number];
        }
        if (hex.length === 8) {
          const r = (parsed >> 24) & 0xff;
          const g = (parsed >> 16) & 0xff;
          const b = (parsed >> 8) & 0xff;
          const a = parsed & 0xff;
          return [r, g, b, a] as [number, number, number, number];
        }
      }
    }
    if (name in named) {
      const [r, g, b] = named[name];
      return [r, g, b, 255] as [number, number, number, number];
    }
  }
  return undefined;
};

export const extractTransform = (props: NodeProps) => {
  const t: Partial<Record<(typeof transformFields)[number], number>> = {};
  for (const key of transformFields) {
    const v = props[key];
    if (typeof v === "number" && Number.isFinite(v)) {
      t[key] = v;
    }
  }
  return t;
};

export const extractVisual = (props: NodeProps) => {
  const v: Partial<Record<(typeof visualFields)[number], number | boolean>> = {};
  for (const key of visualFields) {
    const raw = props[key];
    if (raw == null) continue;
    if (key === "background" || key === "textColor") {
      v[key] = packColor(raw as ColorInput);
      continue;
    }
    if (key === "clipChildren") {
      v[key] = Boolean(raw);
      continue;
    }
    if (typeof raw === "number" && Number.isFinite(raw)) {
      v[key] = raw;
    }
  }
  return v;
};
