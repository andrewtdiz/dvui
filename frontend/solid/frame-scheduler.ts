export type FrameStep = () => boolean | void;

type SchedulerOptions = {
  /**
   * Interval in milliseconds between frames. Zero or undefined uses setImmediate for maximum pace.
   */
  intervalMs?: number;
};

export const createFrameScheduler = (options: SchedulerOptions = {}) => {
  let running = false;
  let timer: NodeJS.Timeout | undefined;
  const intervalMs = options.intervalMs ?? 0;

  const scheduleNext = (step: FrameStep) => {
    if (!running) return;
    if (intervalMs > 0) {
      timer = setTimeout(() => run(step), intervalMs);
    } else {
      setImmediate(() => run(step));
    }
  };

  const run = (step: FrameStep) => {
    if (!running) return;
    const keepGoing = step();
    if (keepGoing === false) {
      running = false;
      return;
    }
    scheduleNext(step);
  };

  return {
    start(step: FrameStep) {
      if (running) return;
      running = true;
      scheduleNext(step);
    },
    stop() {
      running = false;
      if (timer) {
        clearTimeout(timer);
        timer = undefined;
      }
    },
    get isRunning() {
      return running;
    },
  };
};
