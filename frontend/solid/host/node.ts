export type ColorInput =
  | string
  | number
  | [number, number, number]
  | [number, number, number, number]
  | Uint8Array
  | Uint8ClampedArray;

export type AnchorSide = "top" | "bottom" | "left" | "right";
export type AnchorAlign = "start" | "center" | "end";
export type IconKind = "auto" | "svg" | "tvg" | "image" | "raster" | "glyph";

export type NodeProps = {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  color?: ColorInput;
  text?: string;
  value?: string | number;
  src?: string;
  iconKind?: IconKind;
  iconGlyph?: string;
  class?: string;
  className?: string;
  rotation?: number;
  scaleX?: number;
  scaleY?: number;
  anchorX?: number;
  anchorY?: number;
  translateX?: number;
  translateY?: number;
  opacity?: number;
  cornerRadius?: number;
  background?: ColorInput;
  textColor?: ColorInput;
  clipChildren?: boolean;
  scroll?: boolean;
  scrollX?: number;
  scrollY?: number;
  canvasWidth?: number;
  canvasHeight?: number;
  autoCanvas?: boolean;
  tabIndex?: number;
  focusTrap?: boolean;
  roving?: boolean;
  modal?: boolean;
  anchorId?: number;
  anchorSide?: AnchorSide;
  anchorAlign?: AnchorAlign;
  anchorOffset?: number;
  role?: string;
  ariaLabel?: string;
  ariaDescription?: string;
  ariaExpanded?: boolean;
  ariaSelected?: boolean;
  ariaChecked?: boolean | "mixed";
  ariaPressed?: boolean | "mixed";
  ariaHidden?: boolean;
  ariaDisabled?: boolean;
  ariaHasPopup?: string | boolean;
  ariaModal?: boolean;
};

export type EventHandler = (payload: Uint8Array) => void;

let nextId = 1;

export class HostNode {
  readonly id = nextId++;
  readonly tag: string;
  parent?: HostNode;
  children: HostNode[] = [];
  props: NodeProps = {};
  listeners = new Map<string, Set<EventHandler>>();
  sentListeners = new Set<string>();
  listenersDirty = false;
  created = false;

  private _onClick?: EventHandler;
  private _onInput?: EventHandler;
  private _onFocus?: EventHandler;
  private _onBlur?: EventHandler;
  private _onMouseEnter?: EventHandler;
  private _onMouseLeave?: EventHandler;
  private _onKeyDown?: EventHandler;
  private _onKeyUp?: EventHandler;

  constructor(tag: string) {
    this.tag = tag;
  }

  set onClick(handler: EventHandler | undefined) {
    if (this._onClick) this.off("click", this._onClick);
    this._onClick = handler;
    if (handler) this.on("click", handler);
  }
  get onClick() {
    return this._onClick;
  }

  set onInput(handler: EventHandler | undefined) {
    if (this._onInput) this.off("input", this._onInput);
    this._onInput = handler;
    if (handler) this.on("input", handler);
  }
  get onInput() {
    return this._onInput;
  }

  set onFocus(handler: EventHandler | undefined) {
    if (this._onFocus) this.off("focus", this._onFocus);
    this._onFocus = handler;
    if (handler) this.on("focus", handler);
  }
  get onFocus() {
    return this._onFocus;
  }

  set onBlur(handler: EventHandler | undefined) {
    if (this._onBlur) this.off("blur", this._onBlur);
    this._onBlur = handler;
    if (handler) this.on("blur", handler);
  }
  get onBlur() {
    return this._onBlur;
  }

  set onMouseEnter(handler: EventHandler | undefined) {
    if (this._onMouseEnter) this.off("mouseenter", this._onMouseEnter);
    this._onMouseEnter = handler;
    if (handler) this.on("mouseenter", handler);
  }
  get onMouseEnter() {
    return this._onMouseEnter;
  }

  set onMouseLeave(handler: EventHandler | undefined) {
    if (this._onMouseLeave) this.off("mouseleave", this._onMouseLeave);
    this._onMouseLeave = handler;
    if (handler) this.on("mouseleave", handler);
  }
  get onMouseLeave() {
    return this._onMouseLeave;
  }

  set onKeyDown(handler: EventHandler | undefined) {
    if (this._onKeyDown) this.off("keydown", this._onKeyDown);
    this._onKeyDown = handler;
    if (handler) this.on("keydown", handler);
  }
  get onKeyDown() {
    return this._onKeyDown;
  }

  set onKeyUp(handler: EventHandler | undefined) {
    if (this._onKeyUp) this.off("keyup", this._onKeyUp);
    this._onKeyUp = handler;
    if (handler) this.on("keyup", handler);
  }
  get onKeyUp() {
    return this._onKeyUp;
  }

  get firstChild(): HostNode | undefined {
    return this.children[0];
  }

  get lastChild(): HostNode | undefined {
    return this.children.length > 0 ? this.children[this.children.length - 1] : undefined;
  }

  get textContent(): string {
    if (this.tag === "text") return this.props.text ?? "";
    return this.children.map((c) => c.textContent).join("");
  }

  set textContent(val: string) {
    if (this.tag === "text") {
      this.props.text = val;
      return;
    }
    this.children = [];
    const child = new HostNode("text");
    child.props.text = val;
    this.add(child);
  }

  get nodeValue(): string {
    return this.textContent;
  }
  set nodeValue(val: string) {
    this.textContent = val;
  }
  get data(): string {
    return this.textContent;
  }
  set data(val: string) {
    this.textContent = val;
  }

  get nextSibling(): HostNode | undefined {
    if (!this.parent) return undefined;
    const idx = this.parent.children.indexOf(this);
    if (idx === -1) return undefined;
    return this.parent.children[idx + 1];
  }

  get previousSibling(): HostNode | undefined {
    if (!this.parent) return undefined;
    const idx = this.parent.children.indexOf(this);
    if (idx <= 0) return undefined;
    return this.parent.children[idx - 1];
  }

  add(child: HostNode, index = this.children.length) {
    child.parent = this;
    this.children.splice(index, 0, child);
  }

  remove(child: HostNode) {
    const idx = this.children.indexOf(child);
    if (idx >= 0) {
      this.children.splice(idx, 1);
    }
    child.parent = undefined;
  }

  on(event: string, handler: EventHandler) {
    const bucket = this.listeners.get(event) ?? new Set<EventHandler>();
    bucket.add(handler);
    this.listeners.set(event, bucket);
    this.listenersDirty = true;
  }

  off(event: string, handler?: EventHandler) {
    if (!handler) {
      this.listeners.delete(event);
      return;
    }
    const bucket = this.listeners.get(event);
    if (!bucket) return;
    bucket.delete(handler);
    if (bucket.size === 0) {
      this.listeners.delete(event);
    }
  }
}
