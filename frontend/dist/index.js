// @bun
// node_modules/solid-js/dist/dev.js
var sharedConfig = {
  context: undefined,
  registry: undefined,
  effects: undefined,
  done: false,
  getContextId() {
    return getContextId(this.context.count);
  },
  getNextContextId() {
    return getContextId(this.context.count++);
  }
};
function getContextId(count) {
  const num = String(count), len = num.length - 1;
  return sharedConfig.context.id + (len ? String.fromCharCode(96 + len) : "") + num;
}
function setHydrateContext(context) {
  sharedConfig.context = context;
}
function nextHydrateContext() {
  return {
    ...sharedConfig.context,
    id: sharedConfig.getNextContextId(),
    count: 0
  };
}
var IS_DEV = true;
var equalFn = (a, b) => a === b;
var $PROXY = Symbol("solid-proxy");
var SUPPORTS_PROXY = typeof Proxy === "function";
var $TRACK = Symbol("solid-track");
var $DEVCOMP = Symbol("solid-dev-component");
var signalOptions = {
  equals: equalFn
};
var ERROR = null;
var runEffects = runQueue;
var STALE = 1;
var PENDING = 2;
var UNOWNED = {
  owned: null,
  cleanups: null,
  context: null,
  owner: null
};
var Owner = null;
var Transition = null;
var Scheduler = null;
var ExternalSourceConfig = null;
var Listener = null;
var Updates = null;
var Effects = null;
var ExecCount = 0;
var DevHooks = {
  afterUpdate: null,
  afterCreateOwner: null,
  afterCreateSignal: null,
  afterRegisterGraph: null
};
function createRoot(fn, detachedOwner) {
  const listener = Listener, owner = Owner, unowned = fn.length === 0, current = detachedOwner === undefined ? owner : detachedOwner, root = unowned ? {
    owned: null,
    cleanups: null,
    context: null,
    owner: null
  } : {
    owned: null,
    cleanups: null,
    context: current ? current.context : null,
    owner: current
  }, updateFn = unowned ? () => fn(() => {
    throw new Error("Dispose method must be an explicit argument to createRoot function");
  }) : () => fn(() => untrack(() => cleanNode(root)));
  DevHooks.afterCreateOwner && DevHooks.afterCreateOwner(root);
  Owner = root;
  Listener = null;
  try {
    return runUpdates(updateFn, true);
  } finally {
    Listener = listener;
    Owner = owner;
  }
}
function createSignal(value, options) {
  options = options ? Object.assign({}, signalOptions, options) : signalOptions;
  const s = {
    value,
    observers: null,
    observerSlots: null,
    comparator: options.equals || undefined
  };
  {
    if (options.name)
      s.name = options.name;
    if (options.internal) {
      s.internal = true;
    } else {
      registerGraph(s);
      if (DevHooks.afterCreateSignal)
        DevHooks.afterCreateSignal(s);
    }
  }
  const setter = (value2) => {
    if (typeof value2 === "function") {
      if (Transition && Transition.running && Transition.sources.has(s))
        value2 = value2(s.tValue);
      else
        value2 = value2(s.value);
    }
    return writeSignal(s, value2);
  };
  return [readSignal.bind(s), setter];
}
function createRenderEffect(fn, value, options) {
  const c = createComputation(fn, value, false, STALE, options);
  if (Scheduler && Transition && Transition.running)
    Updates.push(c);
  else
    updateComputation(c);
}
function createEffect(fn, value, options) {
  runEffects = runUserEffects;
  const c = createComputation(fn, value, false, STALE, options), s = SuspenseContext && useContext(SuspenseContext);
  if (s)
    c.suspense = s;
  if (!options || !options.render)
    c.user = true;
  Effects ? Effects.push(c) : updateComputation(c);
}
function createMemo(fn, value, options) {
  options = options ? Object.assign({}, signalOptions, options) : signalOptions;
  const c = createComputation(fn, value, true, 0, options);
  c.observers = null;
  c.observerSlots = null;
  c.comparator = options.equals || undefined;
  if (Scheduler && Transition && Transition.running) {
    c.tState = STALE;
    Updates.push(c);
  } else
    updateComputation(c);
  return readSignal.bind(c);
}
function untrack(fn) {
  if (!ExternalSourceConfig && Listener === null)
    return fn();
  const listener = Listener;
  Listener = null;
  try {
    if (ExternalSourceConfig)
      return ExternalSourceConfig.untrack(fn);
    return fn();
  } finally {
    Listener = listener;
  }
}
function onCleanup(fn) {
  if (Owner === null)
    console.warn("cleanups created outside a `createRoot` or `render` will never be run");
  else if (Owner.cleanups === null)
    Owner.cleanups = [fn];
  else
    Owner.cleanups.push(fn);
  return fn;
}
function startTransition(fn) {
  if (Transition && Transition.running) {
    fn();
    return Transition.done;
  }
  const l = Listener;
  const o = Owner;
  return Promise.resolve().then(() => {
    Listener = l;
    Owner = o;
    let t;
    if (Scheduler || SuspenseContext) {
      t = Transition || (Transition = {
        sources: new Set,
        effects: [],
        promises: new Set,
        disposed: new Set,
        queue: new Set,
        running: true
      });
      t.done || (t.done = new Promise((res) => t.resolve = res));
      t.running = true;
    }
    runUpdates(fn, false);
    Listener = Owner = null;
    return t ? t.done : undefined;
  });
}
var [transPending, setTransPending] = /* @__PURE__ */ createSignal(false);
function devComponent(Comp, props) {
  const c = createComputation(() => untrack(() => {
    Object.assign(Comp, {
      [$DEVCOMP]: true
    });
    return Comp(props);
  }), undefined, true, 0);
  c.props = props;
  c.observers = null;
  c.observerSlots = null;
  c.name = Comp.name;
  c.component = Comp;
  updateComputation(c);
  return c.tValue !== undefined ? c.tValue : c.value;
}
function registerGraph(value) {
  if (Owner) {
    if (Owner.sourceMap)
      Owner.sourceMap.push(value);
    else
      Owner.sourceMap = [value];
    value.graph = Owner;
  }
  if (DevHooks.afterRegisterGraph)
    DevHooks.afterRegisterGraph(value);
}
function useContext(context) {
  let value;
  return Owner && Owner.context && (value = Owner.context[context.id]) !== undefined ? value : context.defaultValue;
}
var SuspenseContext;
function readSignal() {
  const runningTransition = Transition && Transition.running;
  if (this.sources && (runningTransition ? this.tState : this.state)) {
    if ((runningTransition ? this.tState : this.state) === STALE)
      updateComputation(this);
    else {
      const updates = Updates;
      Updates = null;
      runUpdates(() => lookUpstream(this), false);
      Updates = updates;
    }
  }
  if (Listener) {
    const sSlot = this.observers ? this.observers.length : 0;
    if (!Listener.sources) {
      Listener.sources = [this];
      Listener.sourceSlots = [sSlot];
    } else {
      Listener.sources.push(this);
      Listener.sourceSlots.push(sSlot);
    }
    if (!this.observers) {
      this.observers = [Listener];
      this.observerSlots = [Listener.sources.length - 1];
    } else {
      this.observers.push(Listener);
      this.observerSlots.push(Listener.sources.length - 1);
    }
  }
  if (runningTransition && Transition.sources.has(this))
    return this.tValue;
  return this.value;
}
function writeSignal(node, value, isComp) {
  let current = Transition && Transition.running && Transition.sources.has(node) ? node.tValue : node.value;
  if (!node.comparator || !node.comparator(current, value)) {
    if (Transition) {
      const TransitionRunning = Transition.running;
      if (TransitionRunning || !isComp && Transition.sources.has(node)) {
        Transition.sources.add(node);
        node.tValue = value;
      }
      if (!TransitionRunning)
        node.value = value;
    } else
      node.value = value;
    if (node.observers && node.observers.length) {
      runUpdates(() => {
        for (let i = 0;i < node.observers.length; i += 1) {
          const o = node.observers[i];
          const TransitionRunning = Transition && Transition.running;
          if (TransitionRunning && Transition.disposed.has(o))
            continue;
          if (TransitionRunning ? !o.tState : !o.state) {
            if (o.pure)
              Updates.push(o);
            else
              Effects.push(o);
            if (o.observers)
              markDownstream(o);
          }
          if (!TransitionRunning)
            o.state = STALE;
          else
            o.tState = STALE;
        }
        if (Updates.length > 1e6) {
          Updates = [];
          if (IS_DEV)
            throw new Error("Potential Infinite Loop Detected.");
          throw new Error;
        }
      }, false);
    }
  }
  return value;
}
function updateComputation(node) {
  if (!node.fn)
    return;
  cleanNode(node);
  const time = ExecCount;
  runComputation(node, Transition && Transition.running && Transition.sources.has(node) ? node.tValue : node.value, time);
  if (Transition && !Transition.running && Transition.sources.has(node)) {
    queueMicrotask(() => {
      runUpdates(() => {
        Transition && (Transition.running = true);
        Listener = Owner = node;
        runComputation(node, node.tValue, time);
        Listener = Owner = null;
      }, false);
    });
  }
}
function runComputation(node, value, time) {
  let nextValue;
  const owner = Owner, listener = Listener;
  Listener = Owner = node;
  try {
    nextValue = node.fn(value);
  } catch (err) {
    if (node.pure) {
      if (Transition && Transition.running) {
        node.tState = STALE;
        node.tOwned && node.tOwned.forEach(cleanNode);
        node.tOwned = undefined;
      } else {
        node.state = STALE;
        node.owned && node.owned.forEach(cleanNode);
        node.owned = null;
      }
    }
    node.updatedAt = time + 1;
    return handleError(err);
  } finally {
    Listener = listener;
    Owner = owner;
  }
  if (!node.updatedAt || node.updatedAt <= time) {
    if (node.updatedAt != null && "observers" in node) {
      writeSignal(node, nextValue, true);
    } else if (Transition && Transition.running && node.pure) {
      Transition.sources.add(node);
      node.tValue = nextValue;
    } else
      node.value = nextValue;
    node.updatedAt = time;
  }
}
function createComputation(fn, init, pure, state = STALE, options) {
  const c = {
    fn,
    state,
    updatedAt: null,
    owned: null,
    sources: null,
    sourceSlots: null,
    cleanups: null,
    value: init,
    owner: Owner,
    context: Owner ? Owner.context : null,
    pure
  };
  if (Transition && Transition.running) {
    c.state = 0;
    c.tState = state;
  }
  if (Owner === null)
    console.warn("computations created outside a `createRoot` or `render` will never be disposed");
  else if (Owner !== UNOWNED) {
    if (Transition && Transition.running && Owner.pure) {
      if (!Owner.tOwned)
        Owner.tOwned = [c];
      else
        Owner.tOwned.push(c);
    } else {
      if (!Owner.owned)
        Owner.owned = [c];
      else
        Owner.owned.push(c);
    }
  }
  if (options && options.name)
    c.name = options.name;
  if (ExternalSourceConfig && c.fn) {
    const [track, trigger] = createSignal(undefined, {
      equals: false
    });
    const ordinary = ExternalSourceConfig.factory(c.fn, trigger);
    onCleanup(() => ordinary.dispose());
    const triggerInTransition = () => startTransition(trigger).then(() => inTransition.dispose());
    const inTransition = ExternalSourceConfig.factory(c.fn, triggerInTransition);
    c.fn = (x) => {
      track();
      return Transition && Transition.running ? inTransition.track(x) : ordinary.track(x);
    };
  }
  DevHooks.afterCreateOwner && DevHooks.afterCreateOwner(c);
  return c;
}
function runTop(node) {
  const runningTransition = Transition && Transition.running;
  if ((runningTransition ? node.tState : node.state) === 0)
    return;
  if ((runningTransition ? node.tState : node.state) === PENDING)
    return lookUpstream(node);
  if (node.suspense && untrack(node.suspense.inFallback))
    return node.suspense.effects.push(node);
  const ancestors = [node];
  while ((node = node.owner) && (!node.updatedAt || node.updatedAt < ExecCount)) {
    if (runningTransition && Transition.disposed.has(node))
      return;
    if (runningTransition ? node.tState : node.state)
      ancestors.push(node);
  }
  for (let i = ancestors.length - 1;i >= 0; i--) {
    node = ancestors[i];
    if (runningTransition) {
      let top = node, prev = ancestors[i + 1];
      while ((top = top.owner) && top !== prev) {
        if (Transition.disposed.has(top))
          return;
      }
    }
    if ((runningTransition ? node.tState : node.state) === STALE) {
      updateComputation(node);
    } else if ((runningTransition ? node.tState : node.state) === PENDING) {
      const updates = Updates;
      Updates = null;
      runUpdates(() => lookUpstream(node, ancestors[0]), false);
      Updates = updates;
    }
  }
}
function runUpdates(fn, init) {
  if (Updates)
    return fn();
  let wait = false;
  if (!init)
    Updates = [];
  if (Effects)
    wait = true;
  else
    Effects = [];
  ExecCount++;
  try {
    const res = fn();
    completeUpdates(wait);
    return res;
  } catch (err) {
    if (!wait)
      Effects = null;
    Updates = null;
    handleError(err);
  }
}
function completeUpdates(wait) {
  if (Updates) {
    if (Scheduler && Transition && Transition.running)
      scheduleQueue(Updates);
    else
      runQueue(Updates);
    Updates = null;
  }
  if (wait)
    return;
  let res;
  if (Transition) {
    if (!Transition.promises.size && !Transition.queue.size) {
      const sources = Transition.sources;
      const disposed = Transition.disposed;
      Effects.push.apply(Effects, Transition.effects);
      res = Transition.resolve;
      for (const e2 of Effects) {
        "tState" in e2 && (e2.state = e2.tState);
        delete e2.tState;
      }
      Transition = null;
      runUpdates(() => {
        for (const d of disposed)
          cleanNode(d);
        for (const v of sources) {
          v.value = v.tValue;
          if (v.owned) {
            for (let i = 0, len = v.owned.length;i < len; i++)
              cleanNode(v.owned[i]);
          }
          if (v.tOwned)
            v.owned = v.tOwned;
          delete v.tValue;
          delete v.tOwned;
          v.tState = 0;
        }
        setTransPending(false);
      }, false);
    } else if (Transition.running) {
      Transition.running = false;
      Transition.effects.push.apply(Transition.effects, Effects);
      Effects = null;
      setTransPending(true);
      return;
    }
  }
  const e = Effects;
  Effects = null;
  if (e.length)
    runUpdates(() => runEffects(e), false);
  else
    DevHooks.afterUpdate && DevHooks.afterUpdate();
  if (res)
    res();
}
function runQueue(queue) {
  for (let i = 0;i < queue.length; i++)
    runTop(queue[i]);
}
function scheduleQueue(queue) {
  for (let i = 0;i < queue.length; i++) {
    const item = queue[i];
    const tasks = Transition.queue;
    if (!tasks.has(item)) {
      tasks.add(item);
      Scheduler(() => {
        tasks.delete(item);
        runUpdates(() => {
          Transition.running = true;
          runTop(item);
        }, false);
        Transition && (Transition.running = false);
      });
    }
  }
}
function runUserEffects(queue) {
  let i, userLength = 0;
  for (i = 0;i < queue.length; i++) {
    const e = queue[i];
    if (!e.user)
      runTop(e);
    else
      queue[userLength++] = e;
  }
  if (sharedConfig.context) {
    if (sharedConfig.count) {
      sharedConfig.effects || (sharedConfig.effects = []);
      sharedConfig.effects.push(...queue.slice(0, userLength));
      return;
    }
    setHydrateContext();
  }
  if (sharedConfig.effects && (sharedConfig.done || !sharedConfig.count)) {
    queue = [...sharedConfig.effects, ...queue];
    userLength += sharedConfig.effects.length;
    delete sharedConfig.effects;
  }
  for (i = 0;i < userLength; i++)
    runTop(queue[i]);
}
function lookUpstream(node, ignore) {
  const runningTransition = Transition && Transition.running;
  if (runningTransition)
    node.tState = 0;
  else
    node.state = 0;
  for (let i = 0;i < node.sources.length; i += 1) {
    const source = node.sources[i];
    if (source.sources) {
      const state = runningTransition ? source.tState : source.state;
      if (state === STALE) {
        if (source !== ignore && (!source.updatedAt || source.updatedAt < ExecCount))
          runTop(source);
      } else if (state === PENDING)
        lookUpstream(source, ignore);
    }
  }
}
function markDownstream(node) {
  const runningTransition = Transition && Transition.running;
  for (let i = 0;i < node.observers.length; i += 1) {
    const o = node.observers[i];
    if (runningTransition ? !o.tState : !o.state) {
      if (runningTransition)
        o.tState = PENDING;
      else
        o.state = PENDING;
      if (o.pure)
        Updates.push(o);
      else
        Effects.push(o);
      o.observers && markDownstream(o);
    }
  }
}
function cleanNode(node) {
  let i;
  if (node.sources) {
    while (node.sources.length) {
      const source = node.sources.pop(), index = node.sourceSlots.pop(), obs = source.observers;
      if (obs && obs.length) {
        const n = obs.pop(), s = source.observerSlots.pop();
        if (index < obs.length) {
          n.sourceSlots[s] = index;
          obs[index] = n;
          source.observerSlots[index] = s;
        }
      }
    }
  }
  if (node.tOwned) {
    for (i = node.tOwned.length - 1;i >= 0; i--)
      cleanNode(node.tOwned[i]);
    delete node.tOwned;
  }
  if (Transition && Transition.running && node.pure) {
    reset(node, true);
  } else if (node.owned) {
    for (i = node.owned.length - 1;i >= 0; i--)
      cleanNode(node.owned[i]);
    node.owned = null;
  }
  if (node.cleanups) {
    for (i = node.cleanups.length - 1;i >= 0; i--)
      node.cleanups[i]();
    node.cleanups = null;
  }
  if (Transition && Transition.running)
    node.tState = 0;
  else
    node.state = 0;
  delete node.sourceMap;
}
function reset(node, top) {
  if (!top) {
    node.tState = 0;
    Transition.disposed.add(node);
  }
  if (node.owned) {
    for (let i = 0;i < node.owned.length; i++)
      reset(node.owned[i]);
  }
}
function castError(err) {
  if (err instanceof Error)
    return err;
  return new Error(typeof err === "string" ? err : "Unknown error", {
    cause: err
  });
}
function runErrors(err, fns, owner) {
  try {
    for (const f of fns)
      f(err);
  } catch (e) {
    handleError(e, owner && owner.owner || null);
  }
}
function handleError(err, owner = Owner) {
  const fns = ERROR && owner && owner.context && owner.context[ERROR];
  const error = castError(err);
  if (!fns)
    throw error;
  if (Effects)
    Effects.push({
      fn() {
        runErrors(error, fns, owner);
      },
      state: STALE
    });
  else
    runErrors(error, fns, owner);
}
var FALLBACK = Symbol("fallback");
var hydrationEnabled = false;
function createComponent(Comp, props) {
  if (hydrationEnabled) {
    if (sharedConfig.context) {
      const c = sharedConfig.context;
      setHydrateContext(nextHydrateContext());
      const r = devComponent(Comp, props || {});
      setHydrateContext(c);
      return r;
    }
  }
  return devComponent(Comp, props || {});
}
function trueFn() {
  return true;
}
var propTraps = {
  get(_, property, receiver) {
    if (property === $PROXY)
      return receiver;
    return _.get(property);
  },
  has(_, property) {
    if (property === $PROXY)
      return true;
    return _.has(property);
  },
  set: trueFn,
  deleteProperty: trueFn,
  getOwnPropertyDescriptor(_, property) {
    return {
      configurable: true,
      enumerable: true,
      get() {
        return _.get(property);
      },
      set: trueFn,
      deleteProperty: trueFn
    };
  },
  ownKeys(_) {
    return _.keys();
  }
};
function resolveSource(s) {
  return !(s = typeof s === "function" ? s() : s) ? {} : s;
}
function resolveSources() {
  for (let i = 0, length = this.length;i < length; ++i) {
    const v = this[i]();
    if (v !== undefined)
      return v;
  }
}
function mergeProps(...sources) {
  let proxy = false;
  for (let i = 0;i < sources.length; i++) {
    const s = sources[i];
    proxy = proxy || !!s && $PROXY in s;
    sources[i] = typeof s === "function" ? (proxy = true, createMemo(s)) : s;
  }
  if (SUPPORTS_PROXY && proxy) {
    return new Proxy({
      get(property) {
        for (let i = sources.length - 1;i >= 0; i--) {
          const v = resolveSource(sources[i])[property];
          if (v !== undefined)
            return v;
        }
      },
      has(property) {
        for (let i = sources.length - 1;i >= 0; i--) {
          if (property in resolveSource(sources[i]))
            return true;
        }
        return false;
      },
      keys() {
        const keys = [];
        for (let i = 0;i < sources.length; i++)
          keys.push(...Object.keys(resolveSource(sources[i])));
        return [...new Set(keys)];
      }
    }, propTraps);
  }
  const sourcesMap = {};
  const defined = Object.create(null);
  for (let i = sources.length - 1;i >= 0; i--) {
    const source = sources[i];
    if (!source)
      continue;
    const sourceKeys = Object.getOwnPropertyNames(source);
    for (let i2 = sourceKeys.length - 1;i2 >= 0; i2--) {
      const key = sourceKeys[i2];
      if (key === "__proto__" || key === "constructor")
        continue;
      const desc = Object.getOwnPropertyDescriptor(source, key);
      if (!defined[key]) {
        defined[key] = desc.get ? {
          enumerable: true,
          configurable: true,
          get: resolveSources.bind(sourcesMap[key] = [desc.get.bind(source)])
        } : desc.value !== undefined ? desc : undefined;
      } else {
        const sources2 = sourcesMap[key];
        if (sources2) {
          if (desc.get)
            sources2.push(desc.get.bind(source));
          else if (desc.value !== undefined)
            sources2.push(() => desc.value);
        }
      }
    }
  }
  const target = {};
  const definedKeys = Object.keys(defined);
  for (let i = definedKeys.length - 1;i >= 0; i--) {
    const key = definedKeys[i], desc = defined[key];
    if (desc && desc.get)
      Object.defineProperty(target, key, desc);
    else
      target[key] = desc ? desc.value : undefined;
  }
  return target;
}
var narrowedError = (name) => `Attempting to access a stale value from <${name}> that could possibly be undefined. This may occur because you are reading the accessor returned from the component at a time where it has already been unmounted. We recommend cleaning up any stale timers or async, or reading from the initial condition.`;
function Show(props) {
  const keyed = props.keyed;
  const conditionValue = createMemo(() => props.when, undefined, {
    name: "condition value"
  });
  const condition = keyed ? conditionValue : createMemo(conditionValue, undefined, {
    equals: (a, b) => !a === !b,
    name: "condition"
  });
  return createMemo(() => {
    const c = condition();
    if (c) {
      const child = props.children;
      const fn = typeof child === "function" && child.length > 0;
      return fn ? untrack(() => child(keyed ? c : () => {
        if (!untrack(condition))
          throw narrowedError("Show");
        return conditionValue();
      })) : child;
    }
    return props.fallback;
  }, undefined, {
    name: "value"
  });
}
if (globalThis) {
  if (!globalThis.Solid$$)
    globalThis.Solid$$ = true;
  else
    console.warn("You appear to have multiple instances of Solid. This can lead to unexpected behavior.");
}

// node_modules/solid-js/universal/dist/dev.js
var memo = (fn) => createMemo(() => fn());
function createRenderer$1({
  createElement,
  createTextNode,
  isTextNode,
  replaceText,
  insertNode,
  removeNode,
  setProperty,
  getParentNode,
  getFirstChild,
  getNextSibling
}) {
  function insert(parent, accessor, marker, initial) {
    if (marker !== undefined && !initial)
      initial = [];
    if (typeof accessor !== "function")
      return insertExpression(parent, accessor, initial, marker);
    createRenderEffect((current) => insertExpression(parent, accessor(), current, marker), initial);
  }
  function insertExpression(parent, value, current, marker, unwrapArray) {
    while (typeof current === "function")
      current = current();
    if (value === current)
      return current;
    const t = typeof value, multi = marker !== undefined;
    if (t === "string" || t === "number") {
      if (t === "number")
        value = value.toString();
      if (multi) {
        let node = current[0];
        if (node && isTextNode(node)) {
          replaceText(node, value);
        } else
          node = createTextNode(value);
        current = cleanChildren(parent, current, marker, node);
      } else {
        if (current !== "" && typeof current === "string") {
          replaceText(getFirstChild(parent), current = value);
        } else {
          cleanChildren(parent, current, marker, createTextNode(value));
          current = value;
        }
      }
    } else if (value == null || t === "boolean") {
      current = cleanChildren(parent, current, marker);
    } else if (t === "function") {
      createRenderEffect(() => {
        let v = value();
        while (typeof v === "function")
          v = v();
        current = insertExpression(parent, v, current, marker);
      });
      return () => current;
    } else if (Array.isArray(value)) {
      const array = [];
      if (normalizeIncomingArray(array, value, unwrapArray)) {
        createRenderEffect(() => current = insertExpression(parent, array, current, marker, true));
        return () => current;
      }
      if (array.length === 0) {
        const replacement = cleanChildren(parent, current, marker);
        if (multi)
          return current = replacement;
      } else {
        if (Array.isArray(current)) {
          if (current.length === 0) {
            appendNodes(parent, array, marker);
          } else
            reconcileArrays(parent, current, array);
        } else if (current == null || current === "") {
          appendNodes(parent, array);
        } else {
          reconcileArrays(parent, multi && current || [getFirstChild(parent)], array);
        }
      }
      current = array;
    } else {
      if (Array.isArray(current)) {
        if (multi)
          return current = cleanChildren(parent, current, marker, value);
        cleanChildren(parent, current, null, value);
      } else if (current == null || current === "" || !getFirstChild(parent)) {
        insertNode(parent, value);
      } else
        replaceNode(parent, value, getFirstChild(parent));
      current = value;
    }
    return current;
  }
  function normalizeIncomingArray(normalized, array, unwrap) {
    let dynamic = false;
    for (let i = 0, len = array.length;i < len; i++) {
      let item = array[i], t;
      if (item == null || item === true || item === false)
        ;
      else if (Array.isArray(item)) {
        dynamic = normalizeIncomingArray(normalized, item) || dynamic;
      } else if ((t = typeof item) === "string" || t === "number") {
        normalized.push(createTextNode(item));
      } else if (t === "function") {
        if (unwrap) {
          while (typeof item === "function")
            item = item();
          dynamic = normalizeIncomingArray(normalized, Array.isArray(item) ? item : [item]) || dynamic;
        } else {
          normalized.push(item);
          dynamic = true;
        }
      } else
        normalized.push(item);
    }
    return dynamic;
  }
  function reconcileArrays(parentNode, a, b) {
    let bLength = b.length, aEnd = a.length, bEnd = bLength, aStart = 0, bStart = 0, after = getNextSibling(a[aEnd - 1]), map = null;
    while (aStart < aEnd || bStart < bEnd) {
      if (a[aStart] === b[bStart]) {
        aStart++;
        bStart++;
        continue;
      }
      while (a[aEnd - 1] === b[bEnd - 1]) {
        aEnd--;
        bEnd--;
      }
      if (aEnd === aStart) {
        const node = bEnd < bLength ? bStart ? getNextSibling(b[bStart - 1]) : b[bEnd - bStart] : after;
        while (bStart < bEnd)
          insertNode(parentNode, b[bStart++], node);
      } else if (bEnd === bStart) {
        while (aStart < aEnd) {
          if (!map || !map.has(a[aStart]))
            removeNode(parentNode, a[aStart]);
          aStart++;
        }
      } else if (a[aStart] === b[bEnd - 1] && b[bStart] === a[aEnd - 1]) {
        const node = getNextSibling(a[--aEnd]);
        insertNode(parentNode, b[bStart++], getNextSibling(a[aStart++]));
        insertNode(parentNode, b[--bEnd], node);
        a[aEnd] = b[bEnd];
      } else {
        if (!map) {
          map = new Map;
          let i = bStart;
          while (i < bEnd)
            map.set(b[i], i++);
        }
        const index = map.get(a[aStart]);
        if (index != null) {
          if (bStart < index && index < bEnd) {
            let i = aStart, sequence = 1, t;
            while (++i < aEnd && i < bEnd) {
              if ((t = map.get(a[i])) == null || t !== index + sequence)
                break;
              sequence++;
            }
            if (sequence > index - bStart) {
              const node = a[aStart];
              while (bStart < index)
                insertNode(parentNode, b[bStart++], node);
            } else
              replaceNode(parentNode, b[bStart++], a[aStart++]);
          } else
            aStart++;
        } else
          removeNode(parentNode, a[aStart++]);
      }
    }
  }
  function cleanChildren(parent, current, marker, replacement) {
    if (marker === undefined) {
      let removed;
      while (removed = getFirstChild(parent))
        removeNode(parent, removed);
      replacement && insertNode(parent, replacement);
      return "";
    }
    const node = replacement || createTextNode("");
    if (current.length) {
      let inserted = false;
      for (let i = current.length - 1;i >= 0; i--) {
        const el = current[i];
        if (node !== el) {
          const isParent = getParentNode(el) === parent;
          if (!inserted && !i)
            isParent ? replaceNode(parent, node, el) : insertNode(parent, node, marker);
          else
            isParent && removeNode(parent, el);
        } else
          inserted = true;
      }
    } else
      insertNode(parent, node, marker);
    return [node];
  }
  function appendNodes(parent, array, marker) {
    for (let i = 0, len = array.length;i < len; i++)
      insertNode(parent, array[i], marker);
  }
  function replaceNode(parent, newNode, oldNode) {
    insertNode(parent, newNode, oldNode);
    removeNode(parent, oldNode);
  }
  function spreadExpression(node, props, prevProps = {}, skipChildren) {
    props || (props = {});
    if (!skipChildren) {
      createRenderEffect(() => prevProps.children = insertExpression(node, props.children, prevProps.children));
    }
    createRenderEffect(() => props.ref && props.ref(node));
    createRenderEffect(() => {
      for (const prop in props) {
        if (prop === "children" || prop === "ref")
          continue;
        const value = props[prop];
        if (value === prevProps[prop])
          continue;
        setProperty(node, prop, value, prevProps[prop]);
        prevProps[prop] = value;
      }
    });
    return prevProps;
  }
  return {
    render(code, element) {
      let disposer;
      createRoot((dispose) => {
        disposer = dispose;
        insert(element, code());
      });
      return disposer;
    },
    insert,
    spread(node, accessor, skipChildren) {
      if (typeof accessor === "function") {
        createRenderEffect((current) => spreadExpression(node, accessor(), current, skipChildren));
      } else
        spreadExpression(node, accessor, undefined, skipChildren);
    },
    createElement,
    createTextNode,
    insertNode,
    setProp(node, name, value, prev) {
      setProperty(node, name, value, prev);
      return value;
    },
    mergeProps,
    effect: createRenderEffect,
    memo,
    createComponent,
    use(fn, element, arg) {
      return untrack(() => fn(element, arg));
    }
  };
}
function createRenderer(options) {
  const renderer = createRenderer$1(options);
  renderer.mergeProps = mergeProps;
  return renderer;
}

// solid/runtime/bridge.ts
var bridge = {};
var registerRuntimeBridge = (scheduleFlush, registerNode, hostOps) => {
  bridge.scheduleFlush = scheduleFlush;
  bridge.registerNode = registerNode;
  bridge.hostOps = hostOps;
};
var notifyRuntimePropChange = () => {
  bridge.scheduleFlush?.();
};
var registerRuntimeNode = (node) => {
  bridge.registerNode?.(node);
};
var getRuntimeHostOps = () => bridge.hostOps;

// solid/host/props.ts
var toByte = (value) => {
  if (Number.isNaN(value) || !Number.isFinite(value))
    return 0;
  if (value < 0)
    return 0;
  if (value > 255)
    return 255;
  return value | 0;
};
var packColor = (value) => {
  if (typeof value === "number")
    return value >>> 0;
  if (!value)
    return 4294967295;
  if (Array.isArray(value) || value instanceof Uint8Array || value instanceof Uint8ClampedArray) {
    const r = toByte(value[0]);
    const g = toByte(value[1]);
    const b = toByte(value[2]);
    const a = toByte(value[3] ?? 255);
    return (r << 24 | g << 16 | b << 8 | a) >>> 0;
  }
  const normalized = value.startsWith("#") ? value.slice(1) : value;
  const expanded = normalized.length === 6 ? `${normalized}ff` : normalized.length === 8 ? normalized : normalized.padEnd(8, "f");
  const parsed = Number.parseInt(expanded, 16);
  if (Number.isNaN(parsed))
    return 4294967295;
  return parsed >>> 0;
};
var frameFromProps = (props) => ({
  x: props.x ?? 0,
  y: props.y ?? 0,
  width: props.width ?? 0,
  height: props.height ?? 0
});
var transformFields = [
  "rotation",
  "scaleX",
  "scaleY",
  "anchorX",
  "anchorY",
  "translateX",
  "translateY"
];
var visualFields = ["opacity", "cornerRadius", "background", "textColor", "clipChildren"];
var hasAbsoluteClass = (props) => {
  const raw = props.className ?? props.class;
  if (!raw)
    return false;
  return raw.split(/\s+/).map((c) => c.trim()).filter(Boolean).includes("absolute");
};
var bgColorFromClass = (props) => {
  const raw = props.className ?? props.class;
  if (!raw)
    return;
  const tokens = raw.split(/\s+/).filter(Boolean);
  const named = {
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
    "blue-400": [96, 165, 250]
  };
  for (const token of tokens) {
    if (!token.startsWith("bg-"))
      continue;
    const name = token.slice(3);
    if (name.startsWith("[") && name.endsWith("]")) {
      const inner = name.slice(1, -1);
      const hex = inner.startsWith("#") ? inner.slice(1) : inner;
      const parsed = Number.parseInt(hex, 16);
      if (!Number.isNaN(parsed)) {
        if (hex.length === 6) {
          const r = parsed >> 16 & 255;
          const g = parsed >> 8 & 255;
          const b = parsed & 255;
          return [r, g, b, 255];
        }
        if (hex.length === 8) {
          const r = parsed >> 24 & 255;
          const g = parsed >> 16 & 255;
          const b = parsed >> 8 & 255;
          const a = parsed & 255;
          return [r, g, b, a];
        }
      }
    }
    if (name in named) {
      const [r, g, b] = named[name];
      return [r, g, b, 255];
    }
  }
  return;
};
var extractTransform = (props) => {
  const t = {};
  for (const key of transformFields) {
    const v = props[key];
    if (typeof v === "number" && Number.isFinite(v)) {
      t[key] = v;
    }
  }
  return t;
};
var extractVisual = (props) => {
  const v = {};
  for (const key of visualFields) {
    const raw = props[key];
    if (raw == null)
      continue;
    if (key === "background" || key === "textColor") {
      v[key] = packColor(raw);
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

// solid/host/snapshot.ts
var serializeTree = (roots) => {
  const nodes = [];
  const serialize = (node, parentId) => {
    const className = node.props.className ?? node.props.class;
    const entry = {
      id: node.id,
      tag: node.tag,
      parent: parentId
    };
    if (className)
      entry.className = className;
    if (node.tag === "text") {
      entry.text = node.props.text ?? "";
    }
    Object.assign(entry, extractTransform(node.props), extractVisual(node.props));
    nodes.push(entry);
    for (const child of node.children) {
      serialize(child, node.id);
    }
  };
  for (const child of roots) {
    serialize(child, 0);
  }
  return nodes;
};

// solid/host/flush.ts
var emitNode = (node, encoder, parentId) => {
  let downstreamParent = parentId;
  if (node.tag !== "root" && node.tag !== "slot") {
    const frame = frameFromProps(node.props);
    const flags = hasAbsoluteClass(node.props) ? 1 : 0;
    const resolvedColor = node.props.color ?? bgColorFromClass(node.props);
    const packedBackground = resolvedColor == null ? 0 : packColor(resolvedColor);
    if (node.tag === "text") {
      encoder.pushText(node.id, parentId, frame, node.props.text ?? "", packColor(node.props.color), flags);
    } else {
      encoder.pushQuad(node.id, parentId, frame, packedBackground, flags);
    }
    downstreamParent = node.id;
  } else if (node.tag !== "slot") {
    downstreamParent = node.id;
  }
  const nextParent = node.tag === "slot" ? parentId : downstreamParent;
  for (const child of node.children) {
    emitNode(child, encoder, nextParent);
  }
};
var markCreated = (node) => {
  node.created = true;
  for (const child of node.children) {
    markCreated(child);
  }
};
var emitPendingListeners = (node, ops) => {
  for (const [eventType] of node.listeners) {
    if (node.sentListeners.has(eventType))
      continue;
    ops.push({ op: "listen", id: node.id, eventType });
    node.sentListeners.add(eventType);
  }
  node.listenersDirty = false;
};
var createFlushController = (ctx) => {
  const { native, encoder, root, nodeIndex, ops } = ctx;
  const mutationMode = ctx.mutationMode ?? "snapshot_once";
  const treeEncoder = new TextEncoder;
  const mutationsSupported = typeof native.applyOps === "function";
  let flushPending = false;
  let seq = 0;
  let syncedOnce = false;
  let needFullSync = false;
  const snapshotEveryFlush = mutationMode === "snapshot_every_flush";
  const snapshotOnceThenMutations = mutationMode === "snapshot_once";
  const mutationsOnlyAfterSnapshot = mutationMode === "mutations_only";
  const flush = () => {
    flushPending = false;
    const nodes = serializeTree(root.children);
    encoder.reset();
    for (const child of root.children) {
      emitNode(child, encoder, 0);
    }
    for (const node of nodeIndex.values()) {
      if (node.listenersDirty || node.sentListeners.size < node.listeners.size) {
        emitPendingListeners(node, ops);
      }
    }
    if (mutationsOnlyAfterSnapshot && ops.length === 0) {
      for (const n of nodes) {
        if (n.id === 0)
          continue;
        const createOp = {
          op: "create",
          id: n.id,
          parent: n.parent ?? 0,
          before: null,
          tag: n.tag,
          className: n.className,
          text: n.text
        };
        ops.push(createOp);
      }
    }
    if (mutationsSupported && native.applyOps && ops.length > 0 && !needFullSync && (syncedOnce || mutationsOnlyAfterSnapshot)) {
      const payloadObj = { seq: ++seq, ops };
      const payload = treeEncoder.encode(JSON.stringify(payloadObj));
      const ok = native.applyOps(payload);
      ops.length = 0;
      if (!ok) {
        needFullSync = true;
      }
    }
    const shouldSnapshot = !syncedOnce || snapshotEveryFlush || needFullSync || !mutationsSupported && native.setSolidTree != null;
    let sentSnapshot = false;
    if (native.setSolidTree && shouldSnapshot) {
      const payloadObj = { nodes };
      const payload = treeEncoder.encode(JSON.stringify(payloadObj));
      native.setSolidTree(payload);
      markCreated(root);
      syncedOnce = true;
      needFullSync = false;
      ops.length = 0;
      sentSnapshot = true;
      for (const node of nodeIndex.values()) {
        if (node.sentListeners.size > 0) {
          node.sentListeners.clear();
          node.listenersDirty = true;
        }
      }
    }
    if (sentSnapshot && mutationsSupported && native.applyOps) {
      for (const node of nodeIndex.values()) {
        if (node.listenersDirty || node.sentListeners.size < node.listeners.size) {
          emitPendingListeners(node, ops);
        }
      }
      const listenOps = ops.filter((op) => op.op === "listen");
      if (listenOps.length > 0) {
        const payloadObj = { seq: ++seq, ops: listenOps };
        const payload = treeEncoder.encode(JSON.stringify(payloadObj));
        const ok = native.applyOps(payload);
        if (!ok) {
          needFullSync = true;
        }
      }
      ops.length = 0;
    }
    native.commit(encoder);
  };
  const scheduleFlush = () => {
    if (flushPending)
      return;
    flushPending = true;
    queueMicrotask(flush);
  };
  return {
    flush,
    flushIfPending() {
      if (flushPending)
        flush();
    },
    hasPendingFlush() {
      return flushPending;
    },
    scheduleFlush
  };
};
var applyVisualMutation = (node, name, value, ops) => {
  const payload = { op: "set_visual", id: node.id };
  if (name === "background" || name === "textColor") {
    payload[name] = packColor(value);
  } else if (name === "clipChildren") {
    payload.clipChildren = Boolean(value);
  } else if (typeof value === "number" && Number.isFinite(value)) {
    payload[name] = value;
  }
  const hasField = payload.opacity != null || payload.cornerRadius != null || payload.background != null || payload.textColor != null || payload.clipChildren != null;
  if (hasField) {
    ops.push(payload);
  }
};
var applyTransformMutation = (node, name, value, ops) => {
  if (typeof value === "number" && Number.isFinite(value)) {
    const payload = { op: "set_transform", id: node.id, [name]: value };
    ops.push(payload);
  }
};
var isTransformField = (name) => {
  return transformFields.includes(name);
};
var isVisualField = (name) => {
  return visualFields.includes(name);
};

// solid/host/node.ts
var nextId = 1;

class HostNode {
  id = nextId++;
  tag;
  parent;
  children = [];
  props = {};
  listeners = new Map;
  sentListeners = new Set;
  listenersDirty = false;
  created = false;
  _onClick;
  _onInput;
  _onFocus;
  _onBlur;
  _onMouseEnter;
  _onMouseLeave;
  constructor(tag) {
    this.tag = tag;
  }
  set onClick(handler) {
    if (this._onClick)
      this.off("click", this._onClick);
    this._onClick = handler;
    if (handler)
      this.on("click", handler);
  }
  get onClick() {
    return this._onClick;
  }
  set onInput(handler) {
    if (this._onInput)
      this.off("input", this._onInput);
    this._onInput = handler;
    if (handler)
      this.on("input", handler);
  }
  get onInput() {
    return this._onInput;
  }
  set onFocus(handler) {
    if (this._onFocus)
      this.off("focus", this._onFocus);
    this._onFocus = handler;
    if (handler)
      this.on("focus", handler);
  }
  get onFocus() {
    return this._onFocus;
  }
  set onBlur(handler) {
    if (this._onBlur)
      this.off("blur", this._onBlur);
    this._onBlur = handler;
    if (handler)
      this.on("blur", handler);
  }
  get onBlur() {
    return this._onBlur;
  }
  set onMouseEnter(handler) {
    if (this._onMouseEnter)
      this.off("mouseenter", this._onMouseEnter);
    this._onMouseEnter = handler;
    if (handler)
      this.on("mouseenter", handler);
  }
  get onMouseEnter() {
    return this._onMouseEnter;
  }
  set onMouseLeave(handler) {
    if (this._onMouseLeave)
      this.off("mouseleave", this._onMouseLeave);
    this._onMouseLeave = handler;
    if (handler)
      this.on("mouseleave", handler);
  }
  get onMouseLeave() {
    return this._onMouseLeave;
  }
  get firstChild() {
    return this.children[0];
  }
  get lastChild() {
    return this.children.length > 0 ? this.children[this.children.length - 1] : undefined;
  }
  get textContent() {
    if (this.tag === "text")
      return this.props.text ?? "";
    return this.children.map((c) => c.textContent).join("");
  }
  set textContent(val) {
    if (this.tag === "text") {
      this.props.text = val;
      return;
    }
    this.children = [];
    const child = new HostNode("text");
    child.props.text = val;
    this.add(child);
  }
  get nodeValue() {
    return this.textContent;
  }
  set nodeValue(val) {
    this.textContent = val;
  }
  get data() {
    return this.textContent;
  }
  set data(val) {
    this.textContent = val;
  }
  get nextSibling() {
    if (!this.parent)
      return;
    const idx = this.parent.children.indexOf(this);
    if (idx === -1)
      return;
    return this.parent.children[idx + 1];
  }
  get previousSibling() {
    if (!this.parent)
      return;
    const idx = this.parent.children.indexOf(this);
    if (idx <= 0)
      return;
    return this.parent.children[idx - 1];
  }
  add(child, index = this.children.length) {
    child.parent = this;
    this.children.splice(index, 0, child);
  }
  remove(child) {
    const idx = this.children.indexOf(child);
    if (idx >= 0) {
      this.children.splice(idx, 1);
    }
    child.parent = undefined;
  }
  on(event, handler) {
    const bucket = this.listeners.get(event) ?? new Set;
    bucket.add(handler);
    this.listeners.set(event, bucket);
    this.listenersDirty = true;
  }
  off(event, handler) {
    if (!handler) {
      this.listeners.delete(event);
      return;
    }
    const bucket = this.listeners.get(event);
    if (!bucket)
      return;
    bucket.delete(handler);
    if (bucket.size === 0) {
      this.listeners.delete(event);
    }
  }
}

// solid/host/mutation-queue.ts
var createMutationQueue = () => {
  const ops = [];
  return {
    ops,
    push: (op) => ops.push(op),
    clear: () => {
      ops.length = 0;
    }
  };
};

// solid/host/index.ts
var removeFromIndex = (node, index) => {
  index.delete(node.id);
  for (const child of node.children) {
    removeFromIndex(child, index);
  }
};
var nodeClass = (node) => node.props.className ?? node.props.class;
var createSolidHost = (native) => {
  const encoder = native.encoder;
  const root = new HostNode("root");
  const nodeIndex = new Map([[root.id, root]]);
  const { ops, push } = createMutationQueue();
  const flushController = createFlushController({
    native,
    encoder,
    root,
    nodeIndex,
    ops
  });
  const enqueueCreateOrMove = (parent, node, anchor) => {
    const parentId = parent === root ? 0 : parent.id;
    const beforeId = anchor ? anchor.id : undefined;
    if (!node.created) {
      node.created = true;
      const createOp = {
        op: "create",
        id: node.id,
        parent: parentId,
        before: beforeId,
        tag: node.tag
      };
      if (node.tag === "text")
        createOp.text = node.props.text ?? "";
      const cls = nodeClass(node);
      if (cls)
        createOp.className = cls;
      Object.assign(createOp, extractTransform(node.props), extractVisual(node.props));
      push(createOp);
      for (const [eventType] of node.listeners) {
        push({
          op: "listen",
          id: node.id,
          eventType
        });
        node.sentListeners.add(eventType);
      }
      node.listenersDirty = false;
      return;
    }
    push({
      op: "move",
      id: node.id,
      parent: parentId,
      before: beforeId
    });
  };
  const enqueueText = (node) => {
    if (node.tag !== "text")
      return;
    push({
      op: "set_text",
      id: node.id,
      text: node.props.text ?? ""
    });
  };
  const registerNode = (node) => {
    nodeIndex.set(node.id, node);
    return node;
  };
  const runtimeOps = {
    createElement(tagName) {
      return registerNode(new HostNode(tagName));
    },
    createTextNode(value) {
      const node = registerNode(new HostNode("text"));
      node.props.text = typeof value === "number" ? `${value}` : value;
      return node;
    },
    createSlotNode() {
      return registerNode(new HostNode("slot"));
    },
    replaceText(node, value) {
      if (node.tag !== "text")
        return;
      node.props.text = value;
      if (node.created) {
        enqueueText(node);
      }
      flushController.scheduleFlush();
    },
    insertNode(parent, node, anchor) {
      const targetIndex = anchor ? parent.children.indexOf(anchor) : parent.children.length;
      parent.add(node, targetIndex === -1 ? parent.children.length : targetIndex);
      enqueueCreateOrMove(parent, node, anchor);
      flushController.scheduleFlush();
      return node;
    },
    removeNode(parent, node) {
      parent.remove(node);
      removeFromIndex(node, nodeIndex);
      node.created = false;
      push({ op: "remove", id: node.id });
      flushController.scheduleFlush();
    },
    setProperty(node, name, value, prev) {
      let eventName = null;
      if (name.startsWith("on:")) {
        eventName = name.slice(3);
      } else if (name.startsWith("prop:on") || name.startsWith("prop:On")) {
        const afterPropOn = name.slice(7);
        eventName = afterPropOn.charAt(0).toLowerCase() + afterPropOn.slice(1);
      } else if (name.startsWith("on") && name.length > 2 && name[2] === name[2].toUpperCase()) {
        const rest = name.slice(2);
        eventName = rest.charAt(0).toLowerCase() + rest.slice(1);
      }
      if (eventName) {
        if (typeof prev === "function")
          node.off(eventName, prev);
        if (typeof value === "function")
          node.on(eventName, value);
        flushController.scheduleFlush();
        return;
      }
      node.props[name] = value;
      if (name === "class" || name === "className") {
        if (node.created) {
          const cls = value == null ? "" : String(value);
          push({ op: "set_class", id: node.id, className: cls });
        }
      } else if (node.created && isTransformField(name)) {
        applyTransformMutation(node, name, value, ops);
      } else if (node.created && isVisualField(name)) {
        applyVisualMutation(node, name, value, ops);
      }
      flushController.scheduleFlush();
    }
  };
  const renderer = createRenderer({
    createElement: runtimeOps.createElement,
    createTextNode: runtimeOps.createTextNode,
    createFragment: runtimeOps.createSlotNode,
    isTextNode(node) {
      return node.tag === "text";
    },
    replaceText: runtimeOps.replaceText,
    insertNode: runtimeOps.insertNode,
    removeNode: runtimeOps.removeNode,
    setProperty: runtimeOps.setProperty,
    getParentNode(node) {
      return node.parent;
    },
    getFirstChild(node) {
      return node.children[0];
    },
    getNextSibling(node) {
      if (!node.parent)
        return;
      const idx = node.parent.children.indexOf(node);
      if (idx === -1 || idx === node.parent.children.length - 1)
        return;
      return node.parent.children[idx + 1];
    }
  });
  registerRuntimeBridge(flushController.scheduleFlush, registerNode, {
    ...runtimeOps,
    insert: renderer.insert,
    spread: renderer.spread
  });
  native.onEvent((name, payload) => {
    if (payload.byteLength < 4)
      return;
    const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
    const targetId = view.getUint32(0, true);
    const targets = targetId === 0 ? Array.from(nodeIndex.values()) : [nodeIndex.get(targetId)].filter((node) => !!node);
    if (!targets.length)
      return;
    const sliced = payload.subarray(4);
    for (const node of targets) {
      const handlers = node.listeners.get(name);
      if (!handlers?.size)
        continue;
      for (const handler of handlers) {
        queueMicrotask(() => handler(sliced));
      }
    }
  });
  return {
    render(view) {
      return renderer.render(view, root);
    },
    flush: flushController.flush,
    flushIfPending: flushController.flushIfPending,
    hasPendingFlush: flushController.hasPendingFlush,
    root,
    getNodeIndex() {
      return nodeIndex;
    }
  };
};
var createSolidNativeHost = createSolidHost;
// solid/native/adapter.ts
import { ptr, toArrayBuffer as toArrayBuffer2 } from "bun:ffi";

// solid/native/command-schema.ts
var COMMAND_HEADER_SIZE = 40;

// solid/native/encoder.ts
class CommandEncoder {
  maxCommands;
  maxPayloadBytes;
  headers;
  headerView;
  payload;
  textEncoder = new TextEncoder;
  commandCount = 0;
  payloadOffset = 0;
  constructor(maxCommands = 256, maxPayloadBytes = 16384) {
    this.maxCommands = maxCommands;
    this.maxPayloadBytes = maxPayloadBytes;
    this.headers = new ArrayBuffer(COMMAND_HEADER_SIZE * this.maxCommands);
    this.headerView = new DataView(this.headers);
    this.payload = new Uint8Array(this.maxPayloadBytes);
  }
  reset() {
    this.commandCount = 0;
    this.payloadOffset = 0;
  }
  pushQuad(nodeId, parentId, frame, rgba, flags = 0) {
    this.writeHeader({
      opcode: 1 /* Quad */,
      nodeId,
      parentId,
      frame,
      payloadOffset: 0,
      payloadLength: 0,
      flags,
      extra: rgba >>> 0
    });
  }
  pushText(nodeId, parentId, frame, text, color, flags = 0) {
    const encoded = this.textEncoder.encode(text);
    if (encoded.length + this.payloadOffset > this.payload.byteLength) {
      throw new Error("Command payload buffer exhausted");
    }
    const payloadOffset = this.payloadOffset;
    this.payload.set(encoded, payloadOffset);
    this.payloadOffset += encoded.length;
    this.writeHeader({
      opcode: 2 /* Text */,
      nodeId,
      parentId,
      frame,
      payloadOffset,
      payloadLength: encoded.length,
      flags,
      extra: color ?? 0
    });
  }
  finalize() {
    const headerBytes = this.commandCount * COMMAND_HEADER_SIZE;
    return {
      headers: new Uint8Array(this.headers, 0, headerBytes),
      payload: this.payload.subarray(0, this.payloadOffset),
      count: this.commandCount
    };
  }
  writeHeader(params) {
    if (this.commandCount >= this.maxCommands) {
      throw new Error("Command header buffer exhausted");
    }
    const base = this.commandCount * COMMAND_HEADER_SIZE;
    this.headerView.setUint8(base, params.opcode);
    this.headerView.setUint8(base + 1, params.flags ?? 0);
    this.headerView.setUint16(base + 2, 0, true);
    this.headerView.setUint32(base + 4, params.nodeId >>> 0, true);
    this.headerView.setUint32(base + 8, params.parentId >>> 0, true);
    this.headerView.setFloat32(base + 12, params.frame.x, true);
    this.headerView.setFloat32(base + 16, params.frame.y, true);
    this.headerView.setFloat32(base + 20, params.frame.width, true);
    this.headerView.setFloat32(base + 24, params.frame.height, true);
    this.headerView.setUint32(base + 28, params.payloadOffset >>> 0, true);
    this.headerView.setUint32(base + 32, params.payloadLength >>> 0, true);
    this.headerView.setUint32(base + 36, params.extra >>> 0, true);
    this.commandCount += 1;
  }
}

// solid/native/ffi.ts
import { existsSync } from "fs";
import { dlopen, JSCallback, suffix, toArrayBuffer } from "bun:ffi";
import { join, resolve } from "path";
var defaultLibName = process.platform === "win32" ? `native_renderer.${suffix}` : process.platform === "darwin" ? `libnative_renderer.${suffix}` : `libnative_renderer.${suffix}`;
var frontendRoot = resolve(import.meta.dir, "..");
var repoRoot = resolve(import.meta.dir, "../..");
var roots = [frontendRoot, repoRoot];
var fallbackNames = ["native_renderer.dll", "libnative_renderer.so", "libnative_renderer.dylib"];
var candidateLibs = [];
for (const root of roots) {
  const binDir = join(root, "zig-out", "bin");
  const libDir = join(root, "zig-out", "lib");
  candidateLibs.push(...fallbackNames.map((name) => join(binDir, name)), ...fallbackNames.map((name) => join(libDir, name)), join(process.platform === "win32" ? binDir : libDir, defaultLibName));
}
var defaultLibPath = candidateLibs.find((p) => existsSync(p)) ?? join(repoRoot, "zig-out", process.platform === "win32" ? "bin" : "lib", defaultLibName);
var binDirs = Array.from(new Set(roots.map((root) => join(root, "zig-out", "bin"))));
var nativeSymbols = {
  createRenderer: {
    args: ["ptr", "ptr"],
    returns: "ptr"
  },
  destroyRenderer: {
    args: ["ptr"],
    returns: "void"
  },
  resizeRenderer: {
    args: ["ptr", "u32", "u32"],
    returns: "void"
  },
  commitCommands: {
    args: ["ptr", "ptr", "usize", "ptr", "usize", "u32"],
    returns: "void"
  },
  presentRenderer: {
    args: ["ptr"],
    returns: "void"
  },
  setRendererText: {
    args: ["ptr", "ptr", "usize"],
    returns: "void"
  },
  setRendererSolidTree: {
    args: ["ptr", "ptr", "usize"],
    returns: "void"
  },
  applyRendererSolidOps: {
    args: ["ptr", "ptr", "usize"],
    returns: "bool"
  },
  getEventRingHeader: {
    args: ["ptr", "ptr", "usize"],
    returns: "usize"
  },
  getEventRingBuffer: {
    args: ["ptr"],
    returns: "ptr"
  },
  getEventRingDetail: {
    args: ["ptr"],
    returns: "ptr"
  },
  acknowledgeEvents: {
    args: ["ptr", "u32"],
    returns: "void"
  }
};
var loadNativeLibrary = (libPath = defaultLibPath) => {
  if (process.platform === "win32") {
    const currentPath = process.env.PATH ?? "";
    const entries = currentPath.split(";");
    const additions = binDirs.filter((dir) => existsSync(dir) && !entries.includes(dir));
    if (additions.length > 0) {
      process.env.PATH = `${additions.join(";")};${currentPath}`;
    }
  }
  return dlopen(libPath, nativeSymbols);
};
var createCallbackBundle = (callbacks = {}) => {
  const decoder = new TextDecoder;
  let onEvent = callbacks.onEvent;
  let onLog = callbacks.onLog;
  const logCallback = new JSCallback((level, msgPtr, msgLenRaw) => {
    if (!onLog || !msgPtr)
      return;
    const msgLen = typeof msgLenRaw === "bigint" ? Number(msgLenRaw) : msgLenRaw;
    if (msgLen === 0)
      return;
    const messageBuffer = new Uint8Array(toArrayBuffer(msgPtr, 0, msgLen));
    const message = decoder.decode(messageBuffer);
    onLog(level, message);
  }, {
    args: ["u8", "ptr", "usize"],
    returns: "void"
  });
  const eventCallback = new JSCallback((namePtr, nameLenRaw, dataPtr, dataLenRaw) => {
    if (!onEvent || !namePtr)
      return;
    const nameLen = typeof nameLenRaw === "bigint" ? Number(nameLenRaw) : nameLenRaw;
    const dataLen = typeof dataLenRaw === "bigint" ? Number(dataLenRaw) : dataLenRaw;
    if (nameLen === 0)
      return;
    const nameBytes = new Uint8Array(toArrayBuffer(namePtr, 0, nameLen));
    const eventName = decoder.decode(nameBytes);
    if (dataLen === 0 || !dataPtr) {
      onEvent(eventName, new Uint8Array(0));
      return;
    }
    const payload = new Uint8Array(toArrayBuffer(dataPtr, 0, dataLen)).slice();
    onEvent(eventName, payload);
  }, {
    args: ["ptr", "usize", "ptr", "usize"],
    returns: "void"
  });
  return {
    log: logCallback,
    event: eventCallback,
    setEventHandler(handler) {
      onEvent = handler;
    },
    setLogHandler(handler) {
      onLog = handler;
    }
  };
};

// solid/native/adapter.ts
class NativeRenderer {
  lib;
  callbacks;
  handle;
  eventHandlers = new Set;
  logHandlers = new Set;
  textEncoder = new TextEncoder;
  callbackDepth = 0;
  closeDeferred = false;
  encoder;
  capabilities = { window: true };
  disposed = false;
  constructor(options = {}) {
    this.lib = loadNativeLibrary(options.libPath);
    if (options.callbacks?.onEvent) {
      this.eventHandlers.add(options.callbacks.onEvent);
    }
    if (options.callbacks?.onLog) {
      this.logHandlers.add(options.callbacks.onLog);
    }
    this.callbacks = createCallbackBundle({
      onEvent: (name, payload) => this.enterCallback(() => {
        for (const handler of this.eventHandlers) {
          handler?.(name, payload);
        }
      }),
      onLog: (level, message) => this.enterCallback(() => {
        for (const handler of this.logHandlers) {
          handler?.(level, message);
        }
      })
    });
    this.encoder = new CommandEncoder(options.maxCommands, options.maxPayload);
    this.handle = this.lib.symbols.createRenderer(this.callbacks.log.ptr, this.callbacks.event.ptr);
    if (!this.handle) {
      throw new Error("Failed to create native renderer handle");
    }
  }
  commit(commands) {
    if (this.disposed)
      return;
    const buffers = commands instanceof CommandEncoder ? commands.finalize() : commands;
    const headersPtr = buffers.headers.byteLength > 0 ? ptr(buffers.headers) : 0;
    const payloadPtr = buffers.payload.byteLength > 0 ? ptr(buffers.payload) : 0;
    this.lib.symbols.commitCommands(this.handle, headersPtr, buffers.headers.byteLength, payloadPtr, buffers.payload.byteLength, buffers.count);
  }
  present() {
    if (this.disposed)
      return;
    this.lib.symbols.presentRenderer(this.handle);
  }
  resize(width, height) {
    if (this.disposed)
      return;
    this.lib.symbols.resizeRenderer(this.handle, width, height);
  }
  setText(text) {
    if (this.disposed)
      return;
    const encoded = this.textEncoder.encode(text);
    this.lib.symbols.setRendererText(this.handle, ptr(encoded), encoded.byteLength);
  }
  setSolidTree(payload) {
    if (this.disposed)
      return;
    const dataPtr = payload.byteLength > 0 ? ptr(payload) : 0;
    this.lib.symbols.setRendererSolidTree(this.handle, dataPtr, payload.byteLength);
  }
  applyOps(payload) {
    if (this.disposed)
      return false;
    const dataPtr = payload.byteLength > 0 ? ptr(payload) : 0;
    return this.lib.symbols.applyRendererSolidOps(this.handle, dataPtr, payload.byteLength);
  }
  onEvent(handler) {
    if (!handler) {
      this.eventHandlers.clear();
      return;
    }
    this.eventHandlers.add(handler);
  }
  onLog(handler) {
    if (!handler) {
      this.logHandlers.clear();
      return;
    }
    this.logHandlers.add(handler);
  }
  close() {
    if (this.disposed)
      return;
    this.lib.symbols.destroyRenderer(this.handle);
    this.disposed = true;
    this.closeDeferred = true;
    this.flushDeferredClose();
  }
  pollEvents(nodeIndex) {
    if (this.disposed)
      return 0;
    const headerBuffer = new Uint8Array(16);
    const copied = this.lib.symbols.getEventRingHeader(this.handle, headerBuffer, headerBuffer.length);
    if (Number(copied) !== headerBuffer.length)
      return 0;
    const headerView = new DataView(headerBuffer.buffer);
    const readHead = headerView.getUint32(0, true);
    const writeHead = headerView.getUint32(4, true);
    const capacity = headerView.getUint32(8, true);
    const detailCapacity = headerView.getUint32(12, true);
    if (readHead === writeHead || capacity === 0)
      return 0;
    const bufferPtr = this.lib.symbols.getEventRingBuffer(this.handle);
    const detailPtr = this.lib.symbols.getEventRingDetail(this.handle);
    if (!bufferPtr)
      return 0;
    const EVENT_ENTRY_SIZE = 16;
    const bufferView = new DataView(toArrayBuffer2(bufferPtr, 0, capacity * EVENT_ENTRY_SIZE));
    const detailBuffer = detailPtr ? new Uint8Array(toArrayBuffer2(detailPtr, 0, detailCapacity)) : new Uint8Array(0);
    const decoder = new TextDecoder;
    const eventKindToName = {
      0: "click",
      1: "input",
      2: "focus",
      3: "blur",
      4: "mouseenter",
      5: "mouseleave",
      6: "keydown",
      7: "keyup",
      8: "change",
      9: "submit"
    };
    let current = readHead;
    let dispatched = 0;
    while (current < writeHead) {
      const idx = current % capacity;
      const offset = idx * EVENT_ENTRY_SIZE;
      const kind = bufferView.getUint8(offset);
      const nodeId = bufferView.getUint32(offset + 4, true);
      const detailOffset = bufferView.getUint32(offset + 8, true);
      const detailLen = bufferView.getUint16(offset + 12, true);
      const eventName = eventKindToName[kind] ?? "unknown";
      const node = nodeIndex.get(nodeId);
      if (node) {
        const handlers = node.listeners.get(eventName);
        if (handlers && handlers.size > 0) {
          let detail;
          if (detailLen > 0 && detailOffset + detailLen <= detailBuffer.length) {
            detail = decoder.decode(detailBuffer.subarray(detailOffset, detailOffset + detailLen));
          }
          const payload = new Uint8Array(4);
          new DataView(payload.buffer).setUint32(0, nodeId, true);
          for (const handler of handlers) {
            try {
              handler(payload);
            } catch (err) {
              console.error(`Event handler error for ${eventName} on node ${nodeId}:`, err);
            }
          }
          dispatched++;
        }
      }
      current++;
    }
    if (current !== readHead) {
      this.lib.symbols.acknowledgeEvents(this.handle, current);
    }
    return dispatched;
  }
  enterCallback(fn) {
    this.callbackDepth += 1;
    try {
      return fn();
    } finally {
      this.callbackDepth -= 1;
      this.flushDeferredClose();
    }
  }
  flushDeferredClose() {
    if (!this.closeDeferred || this.callbackDepth > 0)
      return;
    this.closeDeferred = false;
    this.callbacks.log.close();
    this.callbacks.event.close();
  }
}
// solid/runtime/index.ts
var memo2 = (fn) => createMemo(() => fn());
var createElement = (tag) => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.createElement) {
    return hostOps.createElement(tag);
  }
  const node = new HostNode(tag);
  registerRuntimeNode(node);
  return node;
};
var createTextNode = (value) => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.createTextNode) {
    return hostOps.createTextNode(value);
  }
  const node = new HostNode("text");
  node.props.text = typeof value === "number" ? `${value}` : value;
  registerRuntimeNode(node);
  return node;
};
var insertNode = (parent, node, anchor) => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.insertNode) {
    return hostOps.insertNode(parent, node, anchor);
  }
  if (anchor) {
    const idx = parent.children.indexOf(anchor);
    if (idx >= 0) {
      parent.add(node, idx);
    } else {
      parent.add(node);
    }
  } else {
    parent.add(node);
  }
  notifyRuntimePropChange();
  return node;
};
var removeNode = (parent, node) => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.removeNode) {
    hostOps.removeNode(parent, node);
    return;
  }
  parent.remove(node);
  notifyRuntimePropChange();
};
var setProperty = (node, name, value, prev) => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.setProperty) {
    hostOps.setProperty(node, name, value, prev);
    return;
  }
  if (name.startsWith("on:")) {
    const eventName = name.slice(3);
    if (prev)
      node.off(eventName, prev);
    if (value)
      node.on(eventName, value);
    notifyRuntimePropChange();
    return;
  }
  if (name.startsWith("on") && name.length > 2 && name[2] === name[2].toUpperCase()) {
    const eventName = name.slice(2, 3).toLowerCase() + name.slice(3);
    if (prev)
      node.off(eventName, prev);
    if (value)
      node.on(eventName, value);
    notifyRuntimePropChange();
    return;
  }
  if (name === "class" || name === "className") {
    node.props.className = value;
    node.props.class = value;
    notifyRuntimePropChange();
    return;
  }
  node.props[name] = value;
  notifyRuntimePropChange();
};
var setProp = setProperty;
var createComponent2 = (Comp, props) => {
  return Comp(props);
};
var resolveValue = (input) => {
  let resolved = input;
  while (typeof resolved === "function") {
    resolved = resolved();
  }
  return resolved;
};
var appendContent = (parent, value) => {
  if (value == null || value === true || value === false)
    return false;
  if (typeof value === "string" || typeof value === "number") {
    const textNode = createTextNode(String(value));
    insertNode(parent, textNode);
    return true;
  }
  if (value instanceof HostNode) {
    insertNode(parent, value);
    return true;
  }
  return false;
};
var clearChildren = (node) => {
  const existing = [...node.children];
  for (const child of existing) {
    removeNode(node, child);
  }
};
var applyInsertValue = (parent, value) => {
  const resolved = resolveValue(value);
  clearChildren(parent);
  if (Array.isArray(resolved)) {
    for (const item of resolved) {
      appendContent(parent, resolveValue(item));
    }
  } else {
    appendContent(parent, resolved);
  }
  notifyRuntimePropChange();
};
var insert = (parent, value, anchor) => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.insert) {
    hostOps.insert(parent, value, anchor ?? null);
    return;
  }
  if (anchor) {
    const wrapper = new HostNode("slot");
    applyInsertValue(wrapper, value);
    for (const child of wrapper.children) {
      insertNode(parent, child, anchor);
    }
  } else {
    applyInsertValue(parent, value);
  }
  if (typeof value === "function") {
    createEffect(() => applyInsertValue(parent, value));
  }
};
var effect = (fn, initial) => {
  fn(initial);
  return createEffect(() => fn(initial));
};
// solid/native/dvui-core.ts
import { dlopen as dlopen2, ptr as ptr2, suffix as suffix2, CString } from "bun:ffi";
import { existsSync as existsSync2 } from "fs";
import { join as join2, resolve as resolve2 } from "path";
var frontendRoot2 = resolve2(import.meta.dir, "..");
var repoRoot2 = resolve2(import.meta.dir, "../..");
var roots2 = [frontendRoot2, repoRoot2];
var fallbackNames2 = ["dvui.dll", "libdvui.so", "libdvui.dylib"];
var defaultLibName2 = process.platform === "win32" ? `dvui.${suffix2}` : `libdvui.${suffix2}`;
function findLib(libPath) {
  if (libPath && existsSync2(libPath))
    return libPath;
  const candidates = [];
  for (const root of roots2) {
    const binDir = join2(root, "zig-out", "bin");
    const libDir = join2(root, "zig-out", "lib");
    candidates.push(...fallbackNames2.map((n) => join2(binDir, n)), ...fallbackNames2.map((n) => join2(libDir, n)), join2(process.platform === "win32" ? binDir : libDir, defaultLibName2));
  }
  const found = candidates.find((p) => existsSync2(p));
  if (found)
    return found;
  return join2(repoRoot2, "zig-out", process.platform === "win32" ? "bin" : "lib", defaultLibName2);
}
var coreSymbols = {
  dvui_core_version: { args: [], returns: "ptr" },
  dvui_core_init: { args: ["ptr"], returns: "ptr" },
  dvui_core_deinit: { args: ["ptr"], returns: "void" },
  dvui_core_begin_frame: { args: ["ptr"], returns: "bool" },
  dvui_core_end_frame: { args: ["ptr"], returns: "bool" },
  dvui_core_pointer: { args: ["ptr", "ptr"], returns: "bool" },
  dvui_core_wheel: { args: ["ptr", "ptr"], returns: "bool" },
  dvui_core_key: { args: ["ptr", "ptr"], returns: "bool" },
  dvui_core_text: { args: ["ptr", "ptr"], returns: "bool" },
  dvui_core_commit: { args: ["ptr", "ptr", "usize", "ptr", "usize", "u32"], returns: "bool" }
};
function loadCoreLibrary(libPath) {
  const lib = dlopen2(findLib(libPath), coreSymbols);
  return lib;
}
function makeInitBuffer(opts) {
  const buf = new ArrayBuffer(24);
  const view = new DataView(buf);
  view.setUint8(0, opts.backend ?? 0 /* raylib */);
  view.setFloat32(4, opts.width ?? 800, true);
  view.setFloat32(8, opts.height ?? 600, true);
  view.setUint8(12, opts.vsync ? 1 : 0);
  return { buf, view };
}
function initCore(opts = {}, libPath) {
  const lib = loadCoreLibrary(libPath);
  const titleBuf = new TextEncoder().encode(`${opts.title ?? "dvui"}\x00`);
  const { buf, view } = makeInitBuffer(opts);
  view.setBigUint64(16, BigInt(ptr2(titleBuf)), true);
  const handlePtr = lib.symbols.dvui_core_init(ptr2(new Uint8Array(buf)));
  if (!handlePtr) {
    throw new Error("dvui_core_init returned null");
  }
  const versionPtr = lib.symbols.dvui_core_version();
  const version = versionPtr ? CString.fromPointer(versionPtr) : "unknown";
  const handle = { handle: BigInt(handlePtr), titleBuf };
  const deinit = () => {
    lib.symbols.dvui_core_deinit(handle.handle);
  };
  return { handle, deinit, version };
}
function makePointerEvent(x, y, button, action) {
  const buf = new ArrayBuffer(12);
  const view = new DataView(buf);
  view.setFloat32(0, x, true);
  view.setFloat32(4, y, true);
  view.setUint8(8, button);
  view.setUint8(9, action);
  return new Uint8Array(buf);
}
function makeWheelEvent(dx, dy) {
  const buf = new ArrayBuffer(8);
  const view = new DataView(buf);
  view.setFloat32(0, dx, true);
  view.setFloat32(4, dy, true);
  return new Uint8Array(buf);
}
function makeKeyEvent(code, action, mods) {
  const buf = new ArrayBuffer(6);
  const view = new DataView(buf);
  view.setUint16(0, code, true);
  view.setUint8(2, action);
  view.setUint16(4, mods, true);
  return new Uint8Array(buf);
}
function makeTextEvent(text) {
  const buf = new ArrayBuffer(16);
  const view = new DataView(buf);
  view.setBigUint64(0, BigInt(ptr2(text)), true);
  view.setBigUint64(8, BigInt(text.byteLength), true);
  return { buf: new Uint8Array(buf), text };
}
function createCoreSession(opts = {}, libPath) {
  const lib = loadCoreLibrary(libPath);
  const { handle, deinit, version } = initCore(opts, libPath);
  return {
    handle,
    version,
    beginFrame() {
      return lib.symbols.dvui_core_begin_frame(handle.handle);
    },
    endFrame() {
      return lib.symbols.dvui_core_end_frame(handle.handle);
    },
    pointer(x, y, button, action) {
      const evt = makePointerEvent(x, y, button, action);
      return lib.symbols.dvui_core_pointer(handle.handle, ptr2(evt));
    },
    wheel(dx, dy) {
      const evt = makeWheelEvent(dx, dy);
      return lib.symbols.dvui_core_wheel(handle.handle, ptr2(evt));
    },
    key(code, action, mods) {
      const evt = makeKeyEvent(code, action, mods);
      return lib.symbols.dvui_core_key(handle.handle, ptr2(evt));
    },
    text(utf8) {
      const evt = makeTextEvent(utf8);
      return lib.symbols.dvui_core_text(handle.handle, ptr2(evt.buf));
    },
    commit(headers, payload, count) {
      const hptr = headers.byteLength > 0 ? ptr2(headers) : 0n;
      const pptr = payload.byteLength > 0 ? ptr2(payload) : 0n;
      return lib.symbols.dvui_core_commit(handle.handle, hptr, headers.byteLength, pptr, payload.byteLength, count >>> 0);
    },
    deinit
  };
}

// solid/native/core-renderer.ts
class CoreRenderer {
  encoder;
  capabilities = { window: true };
  disposed = false;
  core = createCoreSession({ backend: 0 /* raylib */, width: 800, height: 450, vsync: true, title: "dvui core" });
  pending;
  eventHandlers = new Set;
  constructor(maxCommands = 512, maxPayload = 64000) {
    this.encoder = new CommandEncoder(maxCommands, maxPayload);
  }
  commit(commands) {
    if (this.disposed)
      return;
    this.pending = commands instanceof CommandEncoder ? commands.finalize() : commands;
  }
  present() {
    if (this.disposed)
      return;
    this.core.beginFrame();
    if (this.pending) {
      const { headers, payload, count } = this.pending;
      this.core.commit(headers, payload, count);
      this.pending = undefined;
    }
    this.core.endFrame();
  }
  resize(_width, _height) {}
  onEvent(handler) {
    if (!handler) {
      this.eventHandlers.clear();
      return;
    }
    this.eventHandlers.add(handler);
  }
  close() {
    if (this.disposed)
      return;
    this.core.deinit();
    this.disposed = true;
  }
}
// solid/util/frame-scheduler.ts
var createFrameScheduler = (options = {}) => {
  let running = false;
  let timer;
  const intervalMs = options.intervalMs ?? 0;
  const scheduleNext = (step) => {
    if (!running)
      return;
    if (intervalMs > 0) {
      timer = setTimeout(() => run(step), intervalMs);
    } else {
      setImmediate(() => run(step));
    }
  };
  const run = (step) => {
    if (!running)
      return;
    const keepGoing = step();
    if (keepGoing === false) {
      running = false;
      return;
    }
    scheduleNext(step);
  };
  return {
    start(step) {
      if (running)
        return;
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
    }
  };
};
// solid/state/time.ts
var [elapsedSeconds, setElapsedSeconds] = createSignal(0);
var [deltaSeconds, setDeltaSeconds] = createSignal(0);
var getElapsedSeconds = elapsedSeconds;
var getDeltaSeconds = deltaSeconds;
var setTime = (elapsed, dt) => {
  setElapsedSeconds(elapsed);
  setDeltaSeconds(dt);
};

// solid/App.tsx
var App = () => {
  const [count, setCount] = createSignal(0);
  const [x, setX] = createSignal(0);
  const [y, setY] = createSignal(0);
  const elapsed = getElapsedSeconds;
  const delta = getDeltaSeconds;
  const radius = 50;
  const center_x = 200;
  const center_y = 150;
  const speed = 3;
  createEffect(() => {
    const t = elapsed();
    const angle = t * speed;
    setX(center_x + Math.cos(angle) * radius);
    setY(center_y + Math.sin(angle) * radius);
  });
  return (() => {
    var _el$ = createElement("div"), _el$2 = createElement("div"), _el$3 = createElement("p"), _el$5 = createElement("button"), _el$6 = createElement("div"), _el$7 = createElement("div"), _el$8 = createElement("p"), _el$0 = createElement("div"), _el$1 = createElement("p"), _el$11 = createElement("div"), _el$12 = createElement("div"), _el$13 = createElement("p"), _el$17 = createElement("p"), _el$18 = createTextNode(`Right `);
    insertNode(_el$, _el$2);
    setProp(_el$, "class", "w-full h-full bg-neutral-900");
    insertNode(_el$2, _el$3);
    insertNode(_el$2, _el$5);
    insertNode(_el$2, _el$6);
    insertNode(_el$2, _el$11);
    insertNode(_el$2, _el$17);
    setProp(_el$2, "class", "absolute top-15 left-15 flex flex-col items-start justify-start border-2 border-red-700 gap-3 bg-red-500 w-64 h-64 p-3 rounded-md");
    insertNode(_el$3, createTextNode(`Centered Text`));
    setProp(_el$3, "class", "absolute top-0 right-0 bg-blue-400 text-gray-100 px-2 py-1 text-center");
    setProp(_el$5, "class", "bg-blue-400 text-gray-100 px-4 py-2 rounded");
    setProp(_el$5, "onClick", (payload) => {
      const view = new DataView(payload.buffer);
      const nodeId = view.getUint32(0, true);
      console.log("[event demo] click payload nodeId=", nodeId);
      setCount((prev) => prev + 1);
    });
    insert(_el$5, count);
    insertNode(_el$6, _el$7);
    insertNode(_el$6, _el$0);
    setProp(_el$6, "class", "w-32 h-32 bg-neutral-800 border border-white rounded-sm");
    insertNode(_el$7, _el$8);
    setProp(_el$7, "class", "absolute top-6 left-6 w-20 h-20 bg-blue-500 z-20 flex items-center justify-center text-white text-sm rounded-sm");
    insertNode(_el$8, createTextNode(`z-20`));
    insertNode(_el$0, _el$1);
    insertNode(_el$1, createTextNode(`z-0`));
    insertNode(_el$11, _el$12);
    insertNode(_el$11, _el$13);
    setProp(_el$11, "class", "w-32 h-32 bg-neutral-800 border border-white overflow-hidden rounded-sm relative");
    setProp(_el$12, "class", "absolute top-0 left-0 w-48 h-48 bg-yellow-400");
    insertNode(_el$13, createTextNode(`clipped`));
    setProp(_el$13, "class", "absolute bottom-1 right-1 text-black text-xs bg-white px-1 rounded-sm");
    insert(_el$2, createComponent2(Show, {
      get when() {
        return memo2(() => count() > 0)() && count() < 10;
      },
      get children() {
        var _el$15 = createElement("p"), _el$16 = createTextNode(`Right `);
        insertNode(_el$15, _el$16);
        setProp(_el$15, "class", "bg-purple-500 text-white rounded-sm");
        insert(_el$15, count, null);
        return _el$15;
      }
    }), _el$17);
    insert(_el$2, (() => {
      var _c$ = memo2(() => !!(count() > 0 && count() < 10));
      return () => _c$() && (() => {
        var _el$19 = createElement("p"), _el$20 = createTextNode(`Right `);
        insertNode(_el$19, _el$20);
        setProp(_el$19, "class", "bg-purple-500 text-white rounded-sm");
        insert(_el$19, count, null);
        return _el$19;
      })();
    })(), _el$17);
    insertNode(_el$17, _el$18);
    setProp(_el$17, "class", "bg-purple-500 text-white rounded-sm");
    insert(_el$17, count, null);
    effect((_$p) => setProp(_el$0, "class", `absolute top-2 left-2 w-20 h-20 bg-green-400 z-${count()}`, _$p));
    return _el$;
  })();
};

// solid/solid-entry.tsx
var createSolidTextApp = (renderer) => {
  const host2 = createSolidNativeHost(renderer);
  const [message, setMessage] = createSignal("Solid to Zig text");
  const dispose = host2.render(App);
  host2.flush();
  return {
    host: host2,
    setMessage,
    dispose: dispose ?? (() => {})
  };
};

// index.ts
var screenWidth = 800;
var screenHeight = 450;
var renderer = new NativeRenderer({
  callbacks: {
    onLog(level, message) {},
    onEvent(name) {
      if (name === "window_closed") {
        shutdown();
      }
    }
  }
});
renderer.resize(screenWidth, screenHeight);
var { host: host2, setMessage, dispose } = createSolidTextApp(renderer);
var scheduler = createFrameScheduler();
var running = true;
var frame = 0;
var startTime = performance.now();
var lastTime = startTime;
var shutdown = () => {
  if (!running)
    return;
  running = false;
  scheduler.stop();
  dispose();
  renderer.close();
};
process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);
process.once("exit", shutdown);
if (undefined) {}
var loop = () => {
  if (!running)
    return false;
  const now = performance.now();
  const dt = (now - lastTime) / 1000;
  const elapsed = (now - startTime) / 1000;
  lastTime = now;
  setTime(elapsed, dt);
  setMessage(`dvui text @ ${elapsed.toFixed(2)}s (frame ${frame})`);
  host2.flush();
  renderer.present();
  const nodeIndex = host2.getNodeIndex?.() ?? new Map;
  renderer.pollEvents(nodeIndex);
  frame += 1;
  return true;
};
scheduler.start(loop);
