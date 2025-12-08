import { createSignal } from "solid-js";

export const [colorRotationEnabled, setColorRotationEnabled] = createSignal(true);

export const toggleColorRotation = () => {
  const next = !colorRotationEnabled();
  setColorRotationEnabled(next);
  return next;
};
