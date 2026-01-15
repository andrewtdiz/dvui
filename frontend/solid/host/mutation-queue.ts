export type MutationMode = "snapshot_once" | "snapshot_every_flush" | "mutations_only";

export type MutationOp = {
  op:
    | "create"
    | "remove"
    | "move"
    | "set_text"
    | "set_class"
    | "set_transform"
    | "set_visual"
    | "set_scroll"
    | "set_focus"
    | "set_anchor"
    | "set_accessibility"
    | "listen"
    | "set";
  id: number;
  parent?: number;
  before?: number | null;
  tag?: string;
  text?: string;
  className?: string;
  eventType?: string;
  name?: string;
  value?: string;
  placeholder?: string;
  src?: string;
  rotation?: number;

  scaleX?: number;
  scaleY?: number;
  anchorX?: number;
  anchorY?: number;
  translateX?: number;
  translateY?: number;
  opacity?: number;
  cornerRadius?: number;
  background?: number;
  textColor?: number;
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
  anchorSide?: string;
  anchorAlign?: string;
  anchorOffset?: number;
  role?: string;
  ariaLabel?: string;
  ariaDescription?: string;
  ariaExpanded?: boolean;
  ariaSelected?: boolean;
  ariaChecked?: string;
  ariaPressed?: string;
  ariaHidden?: boolean;
  ariaDisabled?: boolean;
  ariaHasPopup?: string;
  ariaModal?: boolean;
};

export const createMutationQueue = () => {
  const ops: MutationOp[] = [];
  return {
    ops,
    push: (op: MutationOp) => ops.push(op),
    clear: () => {
      ops.length = 0;
    },
  };
};
