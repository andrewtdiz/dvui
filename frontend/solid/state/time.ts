import { createSignal as WeaveValue } from "solid-js";

const [elapsedSeconds, setElapsedSeconds] = WeaveValue(0);
const [deltaSeconds, setDeltaSeconds] = WeaveValue(0);

export const getElapsedSeconds = elapsedSeconds;
export const getDeltaSeconds = deltaSeconds;

export const setTime = (elapsed: number, dt: number) => {
  setElapsedSeconds(elapsed);
  setDeltaSeconds(dt);
};
