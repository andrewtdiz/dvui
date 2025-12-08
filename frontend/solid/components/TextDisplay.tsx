/** @jsxImportSource solid-js */
import { createMemo } from "solid-js";
import { rgba } from "../color";
import { colorRotationEnabled } from "../state/color-rotation";
import { getElapsedSeconds } from "../state/time";

interface TextDisplayProps {
  message: string;
  center?: { x: number; y: number };
  className?: string;
}

export const TextDisplay = (props: TextDisplayProps) => {
  const text = () => props.message;
  const center = () => props.center ?? { x: 400, y: 225 };

  const position = createMemo(
    () => {
      const t = getElapsedSeconds() * 4;
      const base = center();
      return {
        x: base.x + 50 * Math.cos(t),
        y: base.y + 50 * Math.sin(t),
      };
    },
    center(),
  );

  const color = createMemo(() => {
    if (!colorRotationEnabled()) {
      return rgba(255, 255, 255, 255);
    }
    const t = getElapsedSeconds() * 2;
    const r = 128 + 127 * Math.sin(t);
    const g = 128 + 127 * Math.sin(t + (2 * Math.PI) / 3);
    const b = 128 + 127 * Math.sin(t + (4 * Math.PI) / 3);
    return rgba(Math.round(r), Math.round(g), Math.round(b), 255);
  }, rgba(255, 255, 255, 255));

  return (
    <text
      class={props.className}
      x={position().x}
      y={position().y}
      width={Math.max(160, text().length * 16)}
      height={22}
      color={color()}
    >
      {text()}
    </text>
  );
};
