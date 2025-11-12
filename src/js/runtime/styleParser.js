import { COLOR_SUFFIXES } from "./colors.js"

const FLEX_DIRECTION_CLASSES = Object.freeze({
  "flex-row": "row",
  "flex-col": "column",
});

const JUSTIFY_CLASSES = Object.freeze({
  "justify-start": "start",
  "justify-center": "center",
  "justify-end": "end",
  "justify-between": "space-between",
  "justify-around": "space-around",
});

const ALIGN_ITEMS_CLASSES = Object.freeze({
  "items-start": "start",
  "items-center": "center",
  "items-end": "end",
});

const ALIGN_CONTENT_CLASSES = Object.freeze({
  "content-start": "start",
  "content-center": "center",
  "content-end": "end",
});

const EMPTY_STYLE = Object.freeze({});

// Extend this list with additional prefixed tailwind tokens (e.g. border-, from-)
// without touching the parser loop.
const PREFIX_RESOLVERS = Object.freeze([
  {
    prefix: "bg-",
    offset: 3,
    prop: "backgroundColor",
    resolve: resolveColor,
  },
  {
    prefix: "text-",
    offset: 5,
    prop: "textColor",
    resolve: resolveColor,
  },
  {
    prefix: "w-",
    offset: 2,
    prop: "width",
    resolve: resolveWidth,
  },
]);

// Literal class tokens map directly to property/value pairs here for quick lookup.
const CLASS_TOKEN_TABLE = Object.freeze(buildStaticClassTable());

export function parseClassNames(className, componentState = EMPTY_STYLE) {
  if (typeof className !== "string") {
    return null;
  }

  const length = className.length;
  if (length === 0) {
    return null;
  }

  let index = 0;
  let style = null;
  let mutated = false;

  while (index < length) {
    let code = className.charCodeAt(index);
    if (isTokenSeparator(code)) {
      index++;
      continue;
    }

    const start = index;
    index++;
    while (index < length) {
      code = className.charCodeAt(index);
      if (isTokenSeparator(code)) {
        break;
      }
      index++;
    }

    const rawToken = className.slice(start, index);
    const normalized = normalizeToken(rawToken, componentState);
    if (!normalized) {
      continue;
    }

    let handled = false;
    for (let i = 0; i < PREFIX_RESOLVERS.length; i++) {
      const resolver = PREFIX_RESOLVERS[i];
      if (
        normalized.length > resolver.offset &&
        normalized.startsWith(resolver.prefix)
      ) {
        handled = true;
        const value = resolver.resolve(normalized.slice(resolver.offset));
        if (value != null) {
          if (style === null) {
            style = Object.create(null);
          }
          style[resolver.prop] = value;
          mutated = true;
        }
        break;
      }
    }
    if (handled) {
      continue;
    }

    const entry = CLASS_TOKEN_TABLE[normalized];
    if (entry) {
      if (style === null) {
        style = Object.create(null);
      }
      style[entry[0]] = entry[1];
      mutated = true;
    }
  }

  return mutated ? style : null;
}

function buildStaticClassTable() {
  const table = Object.create(null);
  table.flex = freezePair("display", "flex");
  assignEntries(table, FLEX_DIRECTION_CLASSES, "flexDirection");
  assignEntries(table, JUSTIFY_CLASSES, "justifyContent");
  assignEntries(table, ALIGN_ITEMS_CLASSES, "alignItems");
  assignEntries(table, ALIGN_CONTENT_CLASSES, "alignContent");
  return table;
}

function assignEntries(target, source, property) {
  for (const key of Object.keys(source)) {
    target[key] = freezePair(property, source[key]);
  }
}

function freezePair(prop, value) {
  return Object.freeze([prop, value]);
}

function isTokenSeparator(code) {
  return code <= 32 || code === 160;
}

function normalizeToken(token, _componentState) {
  // Variant support (hover:, focus:, etc.) will plug in here later.
  const separator = token.lastIndexOf(":");
  return separator === -1 ? token : token.slice(separator + 1);
}

function resolveColor(suffix) {
  return COLOR_SUFFIXES[suffix] ?? null;
}

const WIDTH_FULL = "full";
const WIDTH_NUMERIC_PATTERN = /^-?\d+(\.\d+)?$/;
const WIDTH_SCALE_PX = 4;

function resolveWidth(suffix) {
  if (suffix === "full") {
    return WIDTH_FULL;
  }
  if (suffix === "px") {
    return 1;
  }
  if (!WIDTH_NUMERIC_PATTERN.test(suffix)) {
    return null;
  }
  const numeric = Number(suffix);
  if (!Number.isFinite(numeric) || numeric < 0) {
    return null;
  }
  return numeric * WIDTH_SCALE_PX;
}
