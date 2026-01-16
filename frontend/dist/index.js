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
function createContext(defaultValue, options) {
  const id = Symbol("context");
  return {
    id,
    Provider: createProvider(id, options),
    defaultValue
  };
}
function useContext(context) {
  let value;
  return Owner && Owner.context && (value = Owner.context[context.id]) !== undefined ? value : context.defaultValue;
}
function children(fn) {
  const children2 = createMemo(fn);
  const memo = createMemo(() => resolveChildren(children2()), undefined, {
    name: "children"
  });
  memo.toArray = () => {
    const c = memo();
    return Array.isArray(c) ? c : c != null ? [c] : [];
  };
  return memo;
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
function resolveChildren(children2) {
  if (typeof children2 === "function" && !children2.length)
    return resolveChildren(children2());
  if (Array.isArray(children2)) {
    const results = [];
    for (let i = 0;i < children2.length; i++) {
      const result = resolveChildren(children2[i]);
      Array.isArray(result) ? results.push.apply(results, result) : results.push(result);
    }
    return results;
  }
  return children2;
}
function createProvider(id, options) {
  return function provider(props) {
    let res;
    createRenderEffect(() => res = untrack(() => {
      Owner.context = {
        ...Owner.context,
        [id]: props.value
      };
      return children(() => props.children);
    }), undefined, options);
    return res;
  };
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
function splitProps(props, ...keys) {
  const len = keys.length;
  if (SUPPORTS_PROXY && $PROXY in props) {
    const blocked = len > 1 ? keys.flat() : keys[0];
    const res = keys.map((k) => {
      return new Proxy({
        get(property) {
          return k.includes(property) ? props[property] : undefined;
        },
        has(property) {
          return k.includes(property) && property in props;
        },
        keys() {
          return k.filter((property) => (property in props));
        }
      }, propTraps);
    });
    res.push(new Proxy({
      get(property) {
        return blocked.includes(property) ? undefined : props[property];
      },
      has(property) {
        return blocked.includes(property) ? false : (property in props);
      },
      keys() {
        return Object.keys(props).filter((k) => !blocked.includes(k));
      }
    }, propTraps));
    return res;
  }
  const objects = [];
  for (let i = 0;i <= len; i++) {
    objects[i] = {};
  }
  for (const propName of Object.getOwnPropertyNames(props)) {
    let keyIndex = len;
    for (let i = 0;i < keys.length; i++) {
      if (keys[i].includes(propName)) {
        keyIndex = i;
        break;
      }
    }
    const desc = Object.getOwnPropertyDescriptor(props, propName);
    const isDefaultDesc = !desc.get && !desc.set && desc.enumerable && desc.writable && desc.configurable;
    isDefaultDesc ? objects[keyIndex][propName] = desc.value : Object.defineProperty(objects[keyIndex], propName, desc);
  }
  return objects;
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
var scrollFields = ["scroll", "scrollX", "scrollY", "canvasWidth", "canvasHeight", "autoCanvas"];
var focusFields = ["tabIndex", "focusTrap", "roving", "modal"];
var anchorFields = ["anchorId", "anchorSide", "anchorAlign", "anchorOffset"];
var accessibilityFields = [
  "role",
  "ariaLabel",
  "ariaDescription",
  "ariaExpanded",
  "ariaSelected",
  "ariaChecked",
  "ariaPressed",
  "ariaHidden",
  "ariaDisabled",
  "ariaHasPopup",
  "ariaModal"
];
var hasAbsoluteClass = (props) => {
  const raw = props.className ?? props.class;
  if (!raw)
    return false;
  return raw.split(/\s+/).map((c) => c.trim()).filter(Boolean).includes("absolute");
};
var clipChildrenFromClass = (props) => {
  const raw = props.className ?? props.class;
  if (!raw)
    return false;
  return raw.split(/\s+/).map((c) => c.trim()).filter(Boolean).includes("overflow-hidden");
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
var extractScroll = (props) => {
  const s = {};
  for (const key of scrollFields) {
    const raw = props[key];
    if (raw == null)
      continue;
    if (key === "scroll" || key === "autoCanvas") {
      s[key] = Boolean(raw);
      continue;
    }
    if (typeof raw === "number" && Number.isFinite(raw)) {
      s[key] = raw;
    }
  }
  return s;
};
var extractFocus = (props) => {
  const f = {};
  if (typeof props.tabIndex === "number" && Number.isFinite(props.tabIndex)) {
    f.tabIndex = props.tabIndex;
  }
  if (props.focusTrap != null) {
    f.focusTrap = Boolean(props.focusTrap);
  }
  if (props.roving != null) {
    f.roving = Boolean(props.roving);
  }
  if (props.modal != null) {
    f.modal = Boolean(props.modal);
  }
  return f;
};
var anchorSides = ["top", "bottom", "left", "right"];
var anchorAligns = ["start", "center", "end"];
var extractAnchor = (props) => {
  const a = {};
  if (typeof props.anchorId === "number" && Number.isFinite(props.anchorId)) {
    a.anchorId = props.anchorId;
  }
  if (typeof props.anchorSide === "string" && anchorSides.includes(props.anchorSide)) {
    a.anchorSide = props.anchorSide;
  }
  if (typeof props.anchorAlign === "string" && anchorAligns.includes(props.anchorAlign)) {
    a.anchorAlign = props.anchorAlign;
  }
  if (typeof props.anchorOffset === "number" && Number.isFinite(props.anchorOffset)) {
    a.anchorOffset = props.anchorOffset;
  }
  return a;
};
var normalizeAriaBool = (value) => {
  if (typeof value === "boolean")
    return value;
  if (typeof value === "string") {
    const lowered = value.toLowerCase();
    if (lowered === "true")
      return true;
    if (lowered === "false")
      return false;
  }
  return;
};
var normalizeAriaChecked = (value) => {
  if (typeof value === "boolean")
    return value ? "true" : "false";
  if (typeof value === "string") {
    const lowered = value.toLowerCase();
    if (lowered === "true" || lowered === "false" || lowered === "mixed")
      return lowered;
  }
  return;
};
var normalizeAriaHasPopup = (value) => {
  if (typeof value === "string")
    return value;
  if (value === true)
    return "menu";
  return;
};
var normalizeAriaName = (name) => {
  if (!name.startsWith("aria-"))
    return name;
  const base = name.slice(5);
  if (base.length === 0)
    return name;
  const camel = base.replace(/-([a-z])/g, (_, char) => char.toUpperCase());
  return `aria${camel.charAt(0).toUpperCase()}${camel.slice(1)}`;
};
var extractAccessibility = (props) => {
  const a = {};
  if (typeof props.role === "string") {
    a.role = props.role;
  }
  if (typeof props.ariaLabel === "string") {
    a.ariaLabel = props.ariaLabel;
  }
  if (typeof props.ariaDescription === "string") {
    a.ariaDescription = props.ariaDescription;
  }
  const expanded = normalizeAriaBool(props.ariaExpanded);
  if (expanded != null) {
    a.ariaExpanded = expanded;
  }
  const selected = normalizeAriaBool(props.ariaSelected);
  if (selected != null) {
    a.ariaSelected = selected;
  }
  const checked = normalizeAriaChecked(props.ariaChecked);
  if (checked != null) {
    a.ariaChecked = checked;
  }
  const pressed = normalizeAriaChecked(props.ariaPressed);
  if (pressed != null) {
    a.ariaPressed = pressed;
  }
  const hidden = normalizeAriaBool(props.ariaHidden);
  if (hidden != null) {
    a.ariaHidden = hidden;
  }
  const disabled = normalizeAriaBool(props.ariaDisabled);
  if (disabled != null) {
    a.ariaDisabled = disabled;
  }
  const popup = normalizeAriaHasPopup(props.ariaHasPopup);
  if (popup != null) {
    a.ariaHasPopup = popup;
  }
  const modal = normalizeAriaBool(props.ariaModal);
  if (modal != null) {
    a.ariaModal = modal;
  }
  return a;
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
    if (node.props.value != null)
      entry.value = String(node.props.value);
    if (node.props.placeholder != null)
      entry.placeholder = String(node.props.placeholder);
    if (node.props.src != null)
      entry.src = String(node.props.src);
    Object.assign(entry, extractTransform(node.props), extractVisual(node.props), extractScroll(node.props), extractFocus(node.props), extractAnchor(node.props), extractAccessibility(node.props));
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
  const isPassthrough = node.tag === "slot" || node.tag === "portal";
  if (node.tag !== "root" && !isPassthrough) {
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
  } else if (!isPassthrough) {
    downstreamParent = node.id;
  }
  const nextParent = isPassthrough ? parentId : downstreamParent;
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
var queuePendingListeners = (node, ops, pending) => {
  for (const [eventType] of node.listeners) {
    if (node.sentListeners.has(eventType))
      continue;
    ops.push({ op: "listen", id: node.id, eventType });
    pending.push({ node, eventType });
  }
};
var commitPendingListeners = (pending) => {
  if (pending.length === 0)
    return;
  const touched = new Set;
  for (const entry of pending) {
    entry.node.sentListeners.add(entry.eventType);
    touched.add(entry.node);
  }
  for (const node of touched) {
    if (node.sentListeners.size >= node.listeners.size) {
      node.listenersDirty = false;
    }
  }
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
  let mutationsOnlySynced = false;
  const snapshotEveryFlush = mutationMode === "snapshot_every_flush";
  const snapshotOnceThenMutations = mutationMode === "snapshot_once";
  const mutationsOnlyAfterSnapshot = mutationMode === "mutations_only";
  const flush = () => {
    flushPending = false;
    let nodes = null;
    const ensureNodes = () => {
      if (!nodes)
        nodes = serializeTree(root.children);
      return nodes;
    };
    let shouldEncodeCommands = native.setSolidTree == null;
    const pendingListeners = [];
    for (const node of nodeIndex.values()) {
      if (node.listenersDirty || node.sentListeners.size < node.listeners.size) {
        queuePendingListeners(node, ops, pendingListeners);
      }
    }
    const needsCreateOps = mutationsOnlyAfterSnapshot && !mutationsOnlySynced && ops.length === 0;
    if (needsCreateOps) {
      for (const n of ensureNodes()) {
        if (n.id === 0)
          continue;
        const createOp = {
          op: "create",
          id: n.id,
          parent: n.parent ?? 0,
          before: null,
          tag: n.tag,
          className: n.className,
          text: n.text,
          src: n.src,
          value: n.value,
          placeholder: n.placeholder,
          rotation: n.rotation,
          scaleX: n.scaleX,
          scaleY: n.scaleY,
          anchorX: n.anchorX,
          anchorY: n.anchorY,
          translateX: n.translateX,
          translateY: n.translateY,
          opacity: n.opacity,
          cornerRadius: n.cornerRadius,
          background: n.background,
          textColor: n.textColor,
          clipChildren: n.clipChildren,
          scroll: n.scroll,
          scrollX: n.scrollX,
          scrollY: n.scrollY,
          canvasWidth: n.canvasWidth,
          canvasHeight: n.canvasHeight,
          autoCanvas: n.autoCanvas,
          tabIndex: n.tabIndex,
          focusTrap: n.focusTrap,
          roving: n.roving,
          modal: n.modal,
          anchorId: n.anchorId,
          anchorSide: n.anchorSide,
          anchorAlign: n.anchorAlign,
          anchorOffset: n.anchorOffset,
          role: n.role,
          ariaLabel: n.ariaLabel,
          ariaDescription: n.ariaDescription,
          ariaExpanded: n.ariaExpanded,
          ariaSelected: n.ariaSelected,
          ariaChecked: n.ariaChecked,
          ariaPressed: n.ariaPressed,
          ariaHidden: n.ariaHidden,
          ariaDisabled: n.ariaDisabled,
          ariaHasPopup: n.ariaHasPopup,
          ariaModal: n.ariaModal
        };
        ops.push(createOp);
      }
      shouldEncodeCommands = true;
    }
    if (mutationsSupported && native.applyOps && ops.length > 0 && !needFullSync && (syncedOnce || mutationsOnlyAfterSnapshot)) {
      const payloadObj = { seq: ++seq, ops };
      const payload = treeEncoder.encode(JSON.stringify(payloadObj));
      const ok = native.applyOps(payload);
      if (ok) {
        commitPendingListeners(pendingListeners);
        if (mutationsOnlyAfterSnapshot) {
          mutationsOnlySynced = true;
        }
      } else {
        const resyncRequested = !needFullSync;
        needFullSync = true;
        if (resyncRequested)
          scheduleFlush();
      }
      ops.length = 0;
    }
    pendingListeners.length = 0;
    const shouldSnapshot = !syncedOnce || snapshotEveryFlush || needFullSync || !mutationsSupported && native.setSolidTree != null;
    let sentSnapshot = false;
    if (native.setSolidTree && shouldSnapshot) {
      const payloadObj = { nodes: ensureNodes() };
      const payload = treeEncoder.encode(JSON.stringify(payloadObj));
      native.setSolidTree(payload);
      markCreated(root);
      syncedOnce = true;
      if (mutationsOnlyAfterSnapshot) {
        mutationsOnlySynced = true;
      }
      needFullSync = false;
      ops.length = 0;
      sentSnapshot = true;
      shouldEncodeCommands = true;
      for (const node of nodeIndex.values()) {
        if (node.sentListeners.size > 0) {
          node.sentListeners.clear();
          node.listenersDirty = true;
        }
      }
    }
    if (sentSnapshot && mutationsSupported && native.applyOps) {
      pendingListeners.length = 0;
      for (const node of nodeIndex.values()) {
        if (node.listenersDirty || node.sentListeners.size < node.listeners.size) {
          queuePendingListeners(node, ops, pendingListeners);
        }
      }
      if (ops.length > 0) {
        const payloadObj = { seq: ++seq, ops };
        const payload = treeEncoder.encode(JSON.stringify(payloadObj));
        const ok = native.applyOps(payload);
        if (ok) {
          commitPendingListeners(pendingListeners);
        } else {
          const resyncRequested = !needFullSync;
          needFullSync = true;
          if (resyncRequested)
            scheduleFlush();
        }
      }
      ops.length = 0;
      pendingListeners.length = 0;
    }
    if (shouldEncodeCommands) {
      encoder.reset();
      for (const child of root.children) {
        emitNode(child, encoder, 0);
      }
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
var applyScrollMutation = (node, name, value, ops) => {
  const payload = { op: "set_scroll", id: node.id };
  if (name === "scroll") {
    payload.scroll = Boolean(value);
  } else if (name === "autoCanvas") {
    payload.autoCanvas = Boolean(value);
  } else if (typeof value === "number" && Number.isFinite(value)) {
    if (name === "scrollX")
      payload.scrollX = value;
    if (name === "scrollY")
      payload.scrollY = value;
    if (name === "canvasWidth")
      payload.canvasWidth = value;
    if (name === "canvasHeight")
      payload.canvasHeight = value;
  }
  const hasField = payload.scroll != null || payload.scrollX != null || payload.scrollY != null || payload.canvasWidth != null || payload.canvasHeight != null || payload.autoCanvas != null;
  if (hasField) {
    ops.push(payload);
  }
};
var applyFocusMutation = (node, name, value, ops) => {
  const payload = { op: "set_focus", id: node.id };
  if (name === "tabIndex" && typeof value === "number" && Number.isFinite(value)) {
    payload.tabIndex = value;
  } else if (name === "focusTrap") {
    payload.focusTrap = Boolean(value);
  } else if (name === "roving") {
    payload.roving = Boolean(value);
  } else if (name === "modal") {
    payload.modal = Boolean(value);
  }
  const hasField = payload.tabIndex != null || payload.focusTrap != null || payload.roving != null || payload.modal != null;
  if (hasField) {
    ops.push(payload);
  }
};
var applyAnchorMutation = (node, name, value, ops) => {
  const payload = { op: "set_anchor", id: node.id };
  if (name === "anchorId" && typeof value === "number" && Number.isFinite(value)) {
    payload.anchorId = value;
  } else if (name === "anchorSide" && typeof value === "string") {
    payload.anchorSide = value;
  } else if (name === "anchorAlign" && typeof value === "string") {
    payload.anchorAlign = value;
  } else if (name === "anchorOffset" && typeof value === "number" && Number.isFinite(value)) {
    payload.anchorOffset = value;
  }
  const hasField = payload.anchorId != null || payload.anchorSide != null || payload.anchorAlign != null || payload.anchorOffset != null;
  if (hasField) {
    ops.push(payload);
  }
};
var normalizeAriaBool2 = (value) => {
  if (value == null)
    return false;
  if (typeof value === "boolean")
    return value;
  if (typeof value === "string") {
    const lowered = value.toLowerCase();
    if (lowered === "true")
      return true;
    if (lowered === "false")
      return false;
  }
  return Boolean(value);
};
var normalizeAriaChecked2 = (value) => {
  if (value == null)
    return "false";
  if (typeof value === "boolean")
    return value ? "true" : "false";
  if (typeof value === "string") {
    const lowered = value.toLowerCase();
    if (lowered === "true" || lowered === "false" || lowered === "mixed")
      return lowered;
  }
  return;
};
var normalizeAriaHasPopup2 = (value) => {
  if (value == null || value === false)
    return "";
  if (typeof value === "string")
    return value;
  if (value === true)
    return "menu";
  return "";
};
var applyAccessibilityMutation = (node, name, value, ops) => {
  const payload = { op: "set_accessibility", id: node.id };
  if (name === "role") {
    payload.role = value == null ? "" : String(value);
  } else if (name === "ariaLabel") {
    payload.ariaLabel = value == null ? "" : String(value);
  } else if (name === "ariaDescription") {
    payload.ariaDescription = value == null ? "" : String(value);
  } else if (name === "ariaExpanded") {
    payload.ariaExpanded = normalizeAriaBool2(value);
  } else if (name === "ariaSelected") {
    payload.ariaSelected = normalizeAriaBool2(value);
  } else if (name === "ariaChecked") {
    const checked = normalizeAriaChecked2(value);
    if (checked != null)
      payload.ariaChecked = checked;
  } else if (name === "ariaPressed") {
    const pressed = normalizeAriaChecked2(value);
    if (pressed != null)
      payload.ariaPressed = pressed;
  } else if (name === "ariaHidden") {
    payload.ariaHidden = normalizeAriaBool2(value);
  } else if (name === "ariaDisabled") {
    payload.ariaDisabled = normalizeAriaBool2(value);
  } else if (name === "ariaHasPopup") {
    payload.ariaHasPopup = normalizeAriaHasPopup2(value);
  } else if (name === "ariaModal") {
    payload.ariaModal = normalizeAriaBool2(value);
  }
  const hasField = payload.role != null || payload.ariaLabel != null || payload.ariaDescription != null || payload.ariaExpanded != null || payload.ariaSelected != null || payload.ariaChecked != null || payload.ariaPressed != null || payload.ariaHidden != null || payload.ariaDisabled != null || payload.ariaHasPopup != null || payload.ariaModal != null;
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
var isScrollField = (name) => {
  return scrollFields.includes(name);
};
var isFocusField = (name) => {
  return focusFields.includes(name);
};
var isAnchorField = (name) => {
  return anchorFields.includes(name);
};
var isAccessibilityField = (name) => {
  return accessibilityFields.includes(name);
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
  _onKeyDown;
  _onKeyUp;
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
  set onKeyDown(handler) {
    if (this._onKeyDown)
      this.off("keydown", this._onKeyDown);
    this._onKeyDown = handler;
    if (handler)
      this.on("keydown", handler);
  }
  get onKeyDown() {
    return this._onKeyDown;
  }
  set onKeyUp(handler) {
    if (this._onKeyUp)
      this.off("keyup", this._onKeyUp);
    this._onKeyUp = handler;
    if (handler)
      this.on("keyup", handler);
  }
  get onKeyUp() {
    return this._onKeyUp;
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
var normalizeTag = (tagName) => {
  if (tagName === "img")
    return "image";
  return tagName;
};
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
      if (node.props.src != null)
        createOp.src = String(node.props.src);
      if (node.props.value != null)
        createOp.value = String(node.props.value);
      Object.assign(createOp, extractTransform(node.props), extractVisual(node.props), extractScroll(node.props), extractFocus(node.props), extractAnchor(node.props), extractAccessibility(node.props));
      push(createOp);
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
      return registerNode(new HostNode(normalizeTag(tagName)));
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
        const normalized = eventName.toLowerCase();
        if (typeof prev === "function")
          node.off(normalized, prev);
        if (typeof value === "function")
          node.on(normalized, value);
        flushController.scheduleFlush();
        return;
      }
      const propName = normalizeAriaName(name);
      node.props[propName] = value;
      if (propName === "class" || propName === "className") {
        const cls = value == null ? "" : String(value);
        if (node.created) {
          push({ op: "set_class", id: node.id, className: cls });
        }
        const nextClip = clipChildrenFromClass(node.props);
        if (nextClip || node.props.clipChildren != null) {
          if (node.props.clipChildren !== nextClip) {
            node.props.clipChildren = nextClip;
            if (node.created) {
              applyVisualMutation(node, "clipChildren", nextClip, ops);
            }
          }
        }
      } else if (propName === "src") {
        if (node.created) {
          const src = value == null ? "" : String(value);
          push({ op: "set", id: node.id, name: "src", src });
        }
      } else if (propName === "value") {
        if (node.created) {
          const nextValue = value == null ? "" : String(value);
          push({ op: "set", id: node.id, name: "value", value: nextValue });
        }
      } else if (propName === "placeholder") {
        if (node.created) {
          const nextValue = value == null ? "" : String(value);
          push({ op: "set", id: node.id, name: "placeholder", value: nextValue, placeholder: nextValue });
        }
      } else if (node.created && isAccessibilityField(propName)) {
        applyAccessibilityMutation(node, propName, value, ops);
      } else if (node.created && isTransformField(propName)) {
        applyTransformMutation(node, propName, value, ops);
      } else if (node.created && isVisualField(propName)) {
        applyVisualMutation(node, propName, value, ops);
      } else if (node.created && isScrollField(propName)) {
        applyScrollMutation(node, propName, value, ops);
      } else if (node.created && isFocusField(propName)) {
        applyFocusMutation(node, propName, value, ops);
      } else if (node.created && isAnchorField(propName)) {
        applyAnchorMutation(node, propName, value, ops);
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
  headers;
  headerView;
  payload;
  headerCapacity;
  payloadCapacity;
  textEncoder = new TextEncoder;
  commandCount = 0;
  payloadOffset = 0;
  constructor(maxCommands = 256, maxPayloadBytes = 16384) {
    this.headerCapacity = Math.max(1, maxCommands);
    this.payloadCapacity = Math.max(1, maxPayloadBytes);
    this.headers = new ArrayBuffer(COMMAND_HEADER_SIZE * this.headerCapacity);
    this.headerView = new DataView(this.headers);
    this.payload = new Uint8Array(this.payloadCapacity);
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
    this.ensurePayloadCapacity(this.payloadOffset + encoded.length);
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
    this.ensureHeaderCapacity(this.commandCount + 1);
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
  ensureHeaderCapacity(requiredCommands) {
    if (requiredCommands <= this.headerCapacity)
      return;
    let next = this.headerCapacity;
    while (next < requiredCommands) {
      next = next > 0 ? next * 2 : 1;
    }
    const nextBuffer = new ArrayBuffer(COMMAND_HEADER_SIZE * next);
    const nextView = new DataView(nextBuffer);
    const used = this.commandCount * COMMAND_HEADER_SIZE;
    new Uint8Array(nextBuffer).set(new Uint8Array(this.headers, 0, used));
    this.headers = nextBuffer;
    this.headerView = nextView;
    this.headerCapacity = next;
  }
  ensurePayloadCapacity(requiredBytes) {
    if (requiredBytes <= this.payloadCapacity)
      return;
    let next = this.payloadCapacity;
    while (next < requiredBytes) {
      next = next > 0 ? next * 2 : 1;
    }
    const nextPayload = new Uint8Array(next);
    nextPayload.set(this.payload.subarray(0, this.payloadOffset));
    this.payload = nextPayload;
    this.payloadCapacity = next;
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
var EVENT_KIND_TO_NAME = {
  0: "click",
  1: "input",
  2: "focus",
  3: "blur",
  4: "mouseenter",
  5: "mouseleave",
  6: "keydown",
  7: "keyup",
  8: "change",
  9: "submit",
  10: "pointerdown",
  11: "pointermove",
  12: "pointerup",
  13: "pointercancel",
  14: "dragstart",
  15: "drag",
  16: "dragend",
  17: "dragenter",
  18: "dragleave",
  19: "drop",
  20: "scroll"
};
var EVENT_DECODER = new TextDecoder;
var POINTER_EVENT_NAMES = new Set([
  "pointerdown",
  "pointermove",
  "pointerup",
  "pointercancel",
  "dragstart",
  "drag",
  "dragend",
  "dragenter",
  "dragleave",
  "drop"
]);
var decodePointerDetail = (payload) => {
  if (payload.byteLength < 12)
    return;
  const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  return {
    x: view.getFloat32(0, true),
    y: view.getFloat32(4, true),
    button: view.getUint8(8),
    modifiers: view.getUint8(9)
  };
};

class NativeRenderer {
  lib;
  callbacks;
  handle;
  eventHandlers = new Set;
  logHandlers = new Set;
  textEncoder = new TextEncoder;
  callbackDepth = 0;
  closeDeferred = false;
  destroyDeferred = false;
  nativeClosed = false;
  lastEventOverflow = 0;
  lastDetailOverflow = 0;
  headerMismatchLogged = false;
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
    this.disposed = true;
    this.closeDeferred = true;
    if (this.callbackDepth > 0) {
      if (!this.nativeClosed) {
        this.destroyDeferred = true;
      }
      this.flushDeferredClose();
      return;
    }
    if (!this.nativeClosed) {
      this.lib.symbols.destroyRenderer(this.handle);
    }
    this.flushDeferredClose();
  }
  markNativeClosed() {
    if (this.disposed)
      return;
    this.nativeClosed = true;
    this.disposed = true;
    this.closeDeferred = true;
    this.flushDeferredClose();
  }
  pollEvents(nodeIndex) {
    if (this.disposed)
      return 0;
    const expectedHeaderSize = 24;
    const minimumHeaderSize = 16;
    const headerBuffer = new Uint8Array(expectedHeaderSize);
    const copied = Number(this.lib.symbols.getEventRingHeader(this.handle, headerBuffer, headerBuffer.length));
    if (copied === 0)
      return 0;
    if (copied !== expectedHeaderSize && !this.headerMismatchLogged) {
      console.warn(`[native] Event ring header size mismatch (expected ${expectedHeaderSize}, got ${copied}).`);
      this.headerMismatchLogged = true;
    }
    if (copied < minimumHeaderSize)
      return 0;
    const headerView = new DataView(headerBuffer.buffer, 0, copied);
    const readHead = headerView.getUint32(0, true);
    const writeHead = headerView.getUint32(4, true);
    const capacity = headerView.getUint32(8, true);
    const detailCapacity = headerView.getUint32(12, true);
    const hasDroppedCounters = copied >= expectedHeaderSize;
    const droppedEvents = hasDroppedCounters ? headerView.getUint32(16, true) : 0;
    const droppedDetails = hasDroppedCounters ? headerView.getUint32(20, true) : 0;
    if (hasDroppedCounters && (droppedEvents !== this.lastEventOverflow || droppedDetails !== this.lastDetailOverflow)) {
      const eventDelta = droppedEvents >= this.lastEventOverflow ? droppedEvents - this.lastEventOverflow : droppedEvents;
      const detailDelta = droppedDetails >= this.lastDetailOverflow ? droppedDetails - this.lastDetailOverflow : droppedDetails;
      if (eventDelta > 0 || detailDelta > 0) {
        const parts = [];
        if (eventDelta > 0)
          parts.push(`${eventDelta} events`);
        if (detailDelta > 0)
          parts.push(`${detailDelta} detail payloads`);
        console.warn(`[native] Event ring overflow: dropped ${parts.join(" and ")}.`);
      }
      this.lastEventOverflow = droppedEvents;
      this.lastDetailOverflow = droppedDetails;
    }
    if (readHead === writeHead || capacity === 0)
      return 0;
    const bufferPtr = this.lib.symbols.getEventRingBuffer(this.handle);
    const detailPtr = this.lib.symbols.getEventRingDetail(this.handle);
    if (!bufferPtr)
      return 0;
    const EVENT_ENTRY_SIZE = 16;
    const bufferView = new DataView(toArrayBuffer2(bufferPtr, 0, capacity * EVENT_ENTRY_SIZE));
    const detailBuffer = detailPtr ? new Uint8Array(toArrayBuffer2(detailPtr, 0, detailCapacity)) : new Uint8Array(0);
    let current = readHead;
    let dispatched = 0;
    while (current < writeHead) {
      const idx = current % capacity;
      const offset = idx * EVENT_ENTRY_SIZE;
      const kind = bufferView.getUint8(offset);
      const nodeId = bufferView.getUint32(offset + 4, true);
      const detailOffset = bufferView.getUint32(offset + 8, true);
      const detailLen = bufferView.getUint16(offset + 12, true);
      const eventName = EVENT_KIND_TO_NAME[kind] ?? "unknown";
      const node = nodeIndex.get(nodeId);
      if (node) {
        const handlers = node.listeners.get(eventName);
        if (handlers && handlers.size > 0) {
          let detail;
          let pointerDetail;
          if (detailLen > 0 && detailOffset + detailLen <= detailBuffer.length) {
            const detailBytes = detailBuffer.subarray(detailOffset, detailOffset + detailLen);
            if (POINTER_EVENT_NAMES.has(eventName)) {
              pointerDetail = decodePointerDetail(detailBytes);
            }
            if (!pointerDetail) {
              detail = EVENT_DECODER.decode(detailBytes);
            }
          }
          const isKeyEvent = eventName === "keydown" || eventName === "keyup";
          const keyValue = isKeyEvent ? detail : undefined;
          const targetValue = typeof detail === "string" ? detail : undefined;
          const eventDetail = pointerDetail ?? detail;
          const eventObj = {
            type: eventName,
            target: { id: nodeId, value: targetValue, tagName: node.tag },
            currentTarget: { id: nodeId, value: targetValue, tagName: node.tag },
            detail: eventDetail,
            key: keyValue,
            pointer: pointerDetail,
            _nativePayload: new Uint8Array([nodeId & 255, nodeId >> 8 & 255, nodeId >> 16 & 255, nodeId >> 24 & 255])
          };
          for (const handler of handlers) {
            try {
              handler(eventObj);
            } catch (err) {
              console.error(`Event handler error for ${eventName} on node ${nodeId}:`, err);
            }
          }
          dispatched++;
        } else {}
      } else {}
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
    if (this.callbackDepth > 0)
      return;
    if (this.destroyDeferred) {
      this.destroyDeferred = false;
      if (!this.nativeClosed) {
        this.lib.symbols.destroyRenderer(this.handle);
      }
    }
    if (!this.closeDeferred)
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
var normalizeResolvedValue = (resolved) => {
  if (resolved == null || resolved === true || resolved === false)
    return null;
  if (typeof resolved === "string" || typeof resolved === "number")
    return resolved;
  if (resolved instanceof HostNode)
    return resolved;
  return null;
};
var normalizeInsertValue = (value) => {
  const resolved = resolveValue(value);
  if (Array.isArray(resolved)) {
    const items = [];
    for (const entry of resolved) {
      const normalized = normalizeResolvedValue(resolveValue(entry));
      if (normalized != null)
        items.push(normalized);
    }
    return items;
  }
  return normalizeResolvedValue(resolved);
};
var updateTextNode = (node, value) => {
  if (node.tag !== "text")
    return false;
  const nextValue = String(value);
  if (node.props.text === nextValue)
    return false;
  const hostOps = getRuntimeHostOps();
  if (hostOps?.replaceText) {
    hostOps.replaceText(node, nextValue);
  } else {
    node.props.text = nextValue;
  }
  return true;
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
var syncInsertSingle = (parent, value) => {
  const children2 = parent.children;
  if (children2.length === 1) {
    const existing = children2[0];
    if (value instanceof HostNode) {
      if (existing === value)
        return false;
    } else if (existing.tag === "text") {
      return updateTextNode(existing, value);
    }
  }
  clearChildren(parent);
  appendContent(parent, value);
  return true;
};
var syncInsertArray = (parent, values) => {
  const children2 = parent.children;
  if (values.length === 0) {
    if (children2.length === 0)
      return false;
    clearChildren(parent);
    return true;
  }
  if (children2.length !== values.length) {
    clearChildren(parent);
    for (const item of values) {
      appendContent(parent, item);
    }
    return true;
  }
  for (let i = 0;i < values.length; i += 1) {
    const value = values[i];
    const child = children2[i];
    if (value instanceof HostNode) {
      if (child !== value) {
        clearChildren(parent);
        for (const item of values) {
          appendContent(parent, item);
        }
        return true;
      }
    } else if (child.tag !== "text") {
      clearChildren(parent);
      for (const item of values) {
        appendContent(parent, item);
      }
      return true;
    }
  }
  let changed = false;
  for (let i = 0;i < values.length; i += 1) {
    const value = values[i];
    if (typeof value === "string" || typeof value === "number") {
      if (updateTextNode(children2[i], value))
        changed = true;
    }
  }
  return changed;
};
var syncInsertValue = (parent, value) => {
  if (value == null) {
    if (parent.children.length === 0)
      return false;
    clearChildren(parent);
    return true;
  }
  if (Array.isArray(value)) {
    return syncInsertArray(parent, value);
  }
  return syncInsertSingle(parent, value);
};
var applyInsertValue = (parent, value) => {
  const normalized = normalizeInsertValue(value);
  const changed = syncInsertValue(parent, normalized);
  if (changed) {
    notifyRuntimePropChange();
  }
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
var spread = (node, props) => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.spread) {
    hostOps.spread(node, props);
    return node;
  }
  if (!props)
    return node;
  for (const [k, v] of Object.entries(props)) {
    setProperty(node, k, v);
  }
  return node;
};
var mergeProps2 = (...sources) => {
  const out = {};
  for (const src of sources) {
    if (!src)
      continue;
    for (const [k, v] of Object.entries(src)) {
      out[k] = v;
    }
  }
  return out;
};
var parseScrollDetail = (detail) => {
  if (!detail)
    return null;
  let parsed;
  try {
    parsed = JSON.parse(detail);
  } catch {
    return null;
  }
  const offsetX = Number(parsed?.x);
  const offsetY = Number(parsed?.y);
  const viewportWidth = Number(parsed?.viewportW);
  const viewportHeight = Number(parsed?.viewportH);
  const contentWidth = Number(parsed?.contentW);
  const contentHeight = Number(parsed?.contentH);
  if (!Number.isFinite(offsetX) || !Number.isFinite(offsetY) || !Number.isFinite(viewportWidth) || !Number.isFinite(viewportHeight) || !Number.isFinite(contentWidth) || !Number.isFinite(contentHeight)) {
    return null;
  }
  return { offsetX, offsetY, viewportWidth, viewportHeight, contentWidth, contentHeight };
};
var computeVirtualRange = (options) => {
  const itemCount = Math.max(0, Math.floor(options.itemCount));
  const itemSize = options.itemSize > 0 ? options.itemSize : 0;
  const viewportSize = Math.max(0, options.viewportSize);
  const scrollOffset = Math.max(0, options.scrollOffset);
  const overscan = Math.max(0, Math.floor(options.overscan ?? 2));
  if (itemCount == 0 || itemSize == 0) {
    return { start: 0, end: 0, offset: 0 };
  }
  const start = Math.max(0, Math.floor(scrollOffset / itemSize) - overscan);
  const visibleCount = Math.ceil(viewportSize / itemSize) + overscan * 2;
  const end = Math.min(itemCount, start + Math.max(0, visibleCount));
  return { start, end, offset: start * itemSize };
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
// solid/components/button.tsx
var buttonVariantClasses = {
  default: "bg-primary text-primary-foreground hover:bg-neutral-300",
  destructive: "bg-destructive text-destructive-foreground hover:bg-red-500",
  outline: "border border-input bg-transparent text-foreground hover:bg-accent hover:text-accent-foreground",
  secondary: "bg-secondary text-secondary-foreground hover:bg-neutral-800",
  ghost: "bg-transparent text-foreground hover:bg-accent hover:text-accent-foreground",
  link: "bg-transparent text-foreground"
};
var buttonSizeClasses = {
  default: "h-10 px-4 py-2",
  sm: "h-9 px-3 rounded-md",
  lg: "h-11 px-8 rounded-md",
  icon: "h-10 w-10"
};
var Button = (props) => {
  const [local, others] = splitProps(props, ["variant", "size", "class", "children"]);
  const merged = mergeProps({
    variant: "default",
    size: "default"
  }, local);
  const computedClass = () => {
    const userClass = local.class ?? props.className ?? "";
    return [
      "inline-flex items-center justify-center rounded-md text-sm",
      buttonVariantClasses[merged.variant],
      buttonSizeClasses[merged.size],
      props.disabled ? "opacity-50" : "",
      userClass
    ].filter(Boolean).join(" ");
  };
  return (() => {
    var _el$ = createElement("button");
    spread(_el$, mergeProps2({
      get ["class"]() {
        return computedClass();
      }
    }, others), true);
    insert(_el$, () => local.children);
    return _el$;
  })();
};
// solid/components/accordion.tsx
var AccordionContext = createContext();
var useAccordionContext = () => {
  const ctx = useContext(AccordionContext);
  if (!ctx) {
    throw new Error("Accordion components must be used within an <Accordion> container");
  }
  return ctx;
};
var AccordionItemContext = createContext();
var useAccordionItemContext = () => {
  const ctx = useContext(AccordionItemContext);
  if (!ctx) {
    throw new Error("AccordionItem components must be used within an <AccordionItem>");
  }
  return ctx;
};
var Accordion = (props) => {
  const [local, others] = splitProps(props, ["type", "value", "defaultValue", "onChange", "collapsible", "class", "className", "children"]);
  const [internalValue, setInternalValue] = createSignal(local.defaultValue);
  const type = () => local.type ?? "single";
  const isControlled = () => local.value !== undefined;
  const currentValue = () => isControlled() ? local.value : internalValue();
  const setValue = (next) => {
    if (!isControlled()) {
      setInternalValue(next);
    }
    local.onChange?.(next);
  };
  const isOpen = (value) => {
    const valueState = currentValue();
    if (type() === "multiple") {
      return Array.isArray(valueState) && valueState.includes(value);
    }
    return valueState === value;
  };
  const toggle = (value) => {
    if (type() === "multiple") {
      const existing = currentValue();
      const list = Array.isArray(existing) ? existing : [];
      const next = list.includes(value) ? list.filter((item) => item !== value) : [...list, value];
      setValue(next);
      return;
    }
    if (isOpen(value)) {
      if (local.collapsible) {
        setValue(undefined);
      }
      return;
    }
    setValue(value);
  };
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    return ["flex flex-col gap-2", userClass].filter(Boolean).join(" ");
  };
  return createComponent2(AccordionContext.Provider, {
    value: {
      type,
      isOpen,
      toggle
    },
    get children() {
      var _el$ = createElement("div");
      spread(_el$, mergeProps2({
        get ["class"]() {
          return computedClass();
        }
      }, others), true);
      insert(_el$, () => local.children);
      return _el$;
    }
  });
};
var AccordionItem = (props) => {
  const ctx = useAccordionContext();
  const [local, others] = splitProps(props, ["value", "disabled", "class", "className", "children"]);
  const isOpen = () => ctx.isOpen(local.value);
  const disabled = () => Boolean(local.disabled);
  const toggle = () => {
    if (disabled())
      return;
    ctx.toggle(local.value);
  };
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    const state = isOpen() ? "bg-muted" : "bg-transparent";
    const disabledClass = disabled() ? "opacity-50" : "";
    return ["flex flex-col gap-2 rounded-md border border-border p-3", state, disabledClass, userClass].filter(Boolean).join(" ");
  };
  return createComponent2(AccordionItemContext.Provider, {
    value: {
      value: () => local.value,
      isOpen,
      toggle,
      disabled
    },
    get children() {
      var _el$2 = createElement("div");
      spread(_el$2, mergeProps2({
        get ["class"]() {
          return computedClass();
        }
      }, others), true);
      insert(_el$2, () => local.children);
      return _el$2;
    }
  });
};
var AccordionTrigger = (props) => {
  const item = useAccordionItemContext();
  const [local, others] = splitProps(props, ["class", "className", "children", "disabled", "onClick"]);
  const disabled = () => Boolean(local.disabled ?? item.disabled());
  const handleClick = (event) => {
    if (disabled())
      return;
    item.toggle();
    local.onClick?.(event);
  };
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    const base = "flex w-full items-center justify-between text-sm text-foreground";
    const disabledClass = disabled() ? "opacity-50" : "";
    return [base, disabledClass, userClass].filter(Boolean).join(" ");
  };
  return (() => {
    var _el$3 = createElement("button");
    setProp(_el$3, "onClick", handleClick);
    spread(_el$3, mergeProps2({
      get ["class"]() {
        return computedClass();
      },
      get ariaExpanded() {
        return item.isOpen();
      },
      get ariaDisabled() {
        return disabled();
      },
      get disabled() {
        return disabled();
      }
    }, others), true);
    insert(_el$3, () => local.children);
    return _el$3;
  })();
};
var AccordionContent = (props) => {
  const item = useAccordionItemContext();
  const [local, others] = splitProps(props, ["forceMount", "class", "className", "children"]);
  const computedClass = (hidden = false) => {
    const userClass = local.class ?? local.className ?? "";
    const hiddenClass = hidden ? "hidden" : "";
    return ["text-sm text-muted-foreground", hiddenClass, userClass].filter(Boolean).join(" ");
  };
  if (local.forceMount) {
    return (() => {
      var _el$4 = createElement("div");
      spread(_el$4, mergeProps2({
        get ["class"]() {
          return computedClass(!item.isOpen());
        },
        get ariaHidden() {
          return !item.isOpen();
        }
      }, others), true);
      insert(_el$4, () => local.children);
      return _el$4;
    })();
  }
  return createComponent2(Show, {
    get when() {
      return item.isOpen();
    },
    get children() {
      var _el$5 = createElement("div");
      setProp(_el$5, "ariaHidden", false);
      spread(_el$5, mergeProps2({
        get ["class"]() {
          return computedClass(false);
        }
      }, others), true);
      insert(_el$5, () => local.children);
      return _el$5;
    }
  });
};
// solid/components/collapsible.tsx
var CollapsibleContext = createContext();
var useCollapsibleContext = () => {
  const ctx = useContext(CollapsibleContext);
  if (!ctx) {
    throw new Error("Collapsible components must be used within a <Collapsible> container");
  }
  return ctx;
};
var Collapsible = (props) => {
  const [local, others] = splitProps(props, ["open", "defaultOpen", "onChange", "disabled", "class", "className", "children"]);
  const [internalOpen, setInternalOpen] = createSignal(local.defaultOpen ?? false);
  const isControlled = () => local.open !== undefined;
  const isOpen = () => isControlled() ? Boolean(local.open) : internalOpen();
  const setOpen = (next) => {
    if (!isControlled()) {
      setInternalOpen(next);
    }
    local.onChange?.(next);
  };
  const toggle = () => {
    if (local.disabled)
      return;
    setOpen(!isOpen());
  };
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    return ["flex flex-col gap-2", userClass].filter(Boolean).join(" ");
  };
  return createComponent2(CollapsibleContext.Provider, {
    value: {
      open: isOpen,
      setOpen,
      toggle,
      disabled: () => Boolean(local.disabled)
    },
    get children() {
      var _el$ = createElement("div");
      spread(_el$, mergeProps2({
        get ["class"]() {
          return computedClass();
        }
      }, others), true);
      insert(_el$, () => local.children);
      return _el$;
    }
  });
};
var CollapsibleTrigger = (props) => {
  const ctx = useCollapsibleContext();
  const [local, others] = splitProps(props, ["class", "className", "children", "disabled", "onClick"]);
  const disabled = () => Boolean(local.disabled ?? ctx.disabled());
  const handleClick = (event) => {
    if (disabled())
      return;
    ctx.toggle();
    local.onClick?.(event);
  };
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    const base = "flex w-full items-center justify-between text-sm text-foreground";
    const disabledClass = disabled() ? "opacity-50" : "";
    return [base, disabledClass, userClass].filter(Boolean).join(" ");
  };
  return (() => {
    var _el$2 = createElement("button");
    setProp(_el$2, "onClick", handleClick);
    spread(_el$2, mergeProps2({
      get ["class"]() {
        return computedClass();
      },
      get ariaExpanded() {
        return ctx.open();
      },
      get ariaDisabled() {
        return disabled();
      },
      get disabled() {
        return disabled();
      }
    }, others), true);
    insert(_el$2, () => local.children);
    return _el$2;
  })();
};
var CollapsibleContent = (props) => {
  const ctx = useCollapsibleContext();
  const [local, others] = splitProps(props, ["forceMount", "class", "className", "children"]);
  const computedClass = (hidden = false) => {
    const userClass = local.class ?? local.className ?? "";
    const hiddenClass = hidden ? "hidden" : "";
    return ["text-sm text-muted-foreground", hiddenClass, userClass].filter(Boolean).join(" ");
  };
  if (local.forceMount) {
    return (() => {
      var _el$3 = createElement("div");
      spread(_el$3, mergeProps2({
        get ["class"]() {
          return computedClass(!ctx.open());
        },
        get ariaHidden() {
          return !ctx.open();
        }
      }, others), true);
      insert(_el$3, () => local.children);
      return _el$3;
    })();
  }
  return createComponent2(Show, {
    get when() {
      return ctx.open();
    },
    get children() {
      var _el$4 = createElement("div");
      setProp(_el$4, "ariaHidden", false);
      spread(_el$4, mergeProps2({
        get ["class"]() {
          return computedClass(false);
        }
      }, others), true);
      insert(_el$4, () => local.children);
      return _el$4;
    }
  });
};
// solid/components/checkbox.tsx
var Checkbox = (props) => {
  const [internalChecked, setInternalChecked] = createSignal(props.defaultChecked ?? false);
  const isChecked = () => props.checked !== undefined ? props.checked : internalChecked();
  const handleClick = () => {
    if (props.disabled)
      return;
    const newValue = !isChecked();
    if (props.checked === undefined) {
      setInternalChecked(newValue);
    }
    props.onChange?.(newValue);
  };
  const wrapperClass = () => {
    const userClass = props.class ?? props.className ?? "";
    return ["flex items-center gap-2", userClass].filter(Boolean).join(" ");
  };
  const boxClasses = () => {
    const base = isChecked() ? "bg-primary text-primary-foreground border border-primary" : "bg-transparent text-foreground border border-input";
    const size = "h-4 w-4 rounded-sm";
    const disabled = props.disabled ? "opacity-50" : "";
    return ["flex items-center justify-center text-xs", size, base, disabled].filter(Boolean).join(" ");
  };
  const labelClass = () => {
    const disabled = props.disabled ? "opacity-50" : "";
    return ["text-sm text-foreground", disabled].filter(Boolean).join(" ");
  };
  const checkSymbol = () => isChecked() ? "\u2713" : " ";
  return (() => {
    var _el$ = createElement("div"), _el$2 = createElement("button");
    insertNode(_el$, _el$2);
    setProp(_el$2, "onClick", handleClick);
    setProp(_el$2, "role", "checkbox");
    insert(_el$2, checkSymbol);
    insert(_el$, createComponent2(Show, {
      get when() {
        return props.label;
      },
      get children() {
        var _el$3 = createElement("p");
        insert(_el$3, () => props.label);
        effect((_$p) => setProp(_el$3, "class", labelClass(), _$p));
        return _el$3;
      }
    }), null);
    effect((_p$) => {
      var _v$ = wrapperClass(), _v$2 = boxClasses(), _v$3 = props.disabled, _v$4 = isChecked(), _v$5 = props.disabled, _v$6 = props.label;
      _v$ !== _p$.e && (_p$.e = setProp(_el$, "class", _v$, _p$.e));
      _v$2 !== _p$.t && (_p$.t = setProp(_el$2, "class", _v$2, _p$.t));
      _v$3 !== _p$.a && (_p$.a = setProp(_el$2, "disabled", _v$3, _p$.a));
      _v$4 !== _p$.o && (_p$.o = setProp(_el$2, "ariaChecked", _v$4, _p$.o));
      _v$5 !== _p$.i && (_p$.i = setProp(_el$2, "ariaDisabled", _v$5, _p$.i));
      _v$6 !== _p$.n && (_p$.n = setProp(_el$2, "ariaLabel", _v$6, _p$.n));
      return _p$;
    }, {
      e: undefined,
      t: undefined,
      a: undefined,
      o: undefined,
      i: undefined,
      n: undefined
    });
    return _el$;
  })();
};
// solid/components/radio-group.tsx
var RadioGroupContext = createContext();
var useRadioGroupContext = () => {
  const ctx = useContext(RadioGroupContext);
  if (!ctx) {
    throw new Error("Radio components must be used within a <RadioGroup> container");
  }
  return ctx;
};
var RadioGroup = (props) => {
  const [local, others] = splitProps(props, ["value", "defaultValue", "onChange", "class", "className", "children"]);
  const [internalValue, setInternalValue] = createSignal(local.defaultValue);
  const isControlled = () => local.value !== undefined;
  const currentValue = () => isControlled() ? local.value : internalValue();
  const setValue = (value) => {
    if (!isControlled()) {
      setInternalValue(value);
    }
    local.onChange?.(value);
  };
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    return ["flex flex-col gap-2", userClass].filter(Boolean).join(" ");
  };
  return createComponent2(RadioGroupContext.Provider, {
    value: {
      value: currentValue,
      setValue,
      isControlled
    },
    get children() {
      var _el$ = createElement("div");
      setProp(_el$, "role", "radiogroup");
      setProp(_el$, "roving", true);
      spread(_el$, mergeProps2({
        get ["class"]() {
          return computedClass();
        }
      }, others), true);
      insert(_el$, () => local.children);
      return _el$;
    }
  });
};
var Radio = (props) => {
  const ctx = useRadioGroupContext();
  const [local, others] = splitProps(props, ["value", "label", "class", "className", "disabled", "onClick", "onFocus"]);
  const isChecked = () => ctx.value() === local.value;
  const handleActivate = (event) => {
    if (local.disabled)
      return;
    ctx.setValue(local.value);
    return event;
  };
  const handleClick = (event) => {
    handleActivate(event);
    local.onClick?.(event);
  };
  const handleFocus = (event) => {
    handleActivate(event);
    local.onFocus?.(event);
  };
  const wrapperClass = () => {
    const userClass = local.class ?? local.className ?? "";
    return ["flex items-center gap-2", userClass].filter(Boolean).join(" ");
  };
  const radioClasses = () => {
    const base = isChecked() ? "bg-primary text-primary-foreground border border-primary" : "bg-transparent text-foreground border border-input";
    const size = "h-4 w-4 rounded-full";
    const disabled = local.disabled ? "opacity-50" : "";
    return ["flex items-center justify-center text-xs", size, base, disabled].filter(Boolean).join(" ");
  };
  const labelClass = () => {
    const disabled = local.disabled ? "opacity-50" : "";
    return ["text-sm text-foreground", disabled].filter(Boolean).join(" ");
  };
  const dotSymbol = () => isChecked() ? "\u25CF" : " ";
  return (() => {
    var _el$2 = createElement("div"), _el$3 = createElement("button");
    insertNode(_el$2, _el$3);
    setProp(_el$3, "onClick", handleClick);
    setProp(_el$3, "onFocus", handleFocus);
    setProp(_el$3, "role", "radio");
    spread(_el$3, mergeProps2({
      get ["class"]() {
        return radioClasses();
      },
      get disabled() {
        return local.disabled;
      },
      get ariaChecked() {
        return isChecked();
      },
      get ariaDisabled() {
        return local.disabled;
      },
      get ariaLabel() {
        return local.label;
      }
    }, others), true);
    insert(_el$3, dotSymbol);
    insert(_el$2, createComponent2(Show, {
      get when() {
        return local.label;
      },
      get children() {
        var _el$4 = createElement("p");
        insert(_el$4, () => local.label);
        effect((_$p) => setProp(_el$4, "class", labelClass(), _$p));
        return _el$4;
      }
    }), null);
    effect((_$p) => setProp(_el$2, "class", wrapperClass(), _$p));
    return _el$2;
  })();
};
// solid/components/alert.tsx
var alertVariantClasses = {
  default: "bg-background text-foreground border border-border",
  destructive: "bg-background text-destructive border border-destructive",
  success: "bg-background text-emerald-500 border border-emerald-500",
  warning: "bg-background text-amber-500 border border-amber-500"
};
var Alert = (props) => {
  const merged = mergeProps({
    variant: "default"
  }, props);
  const computedClass = () => {
    const variant = alertVariantClasses[merged.variant];
    return `flex flex-col gap-1 rounded-lg p-4 ${variant} ${props.class ?? ""}`;
  };
  return (() => {
    var _el$ = createElement("div"), _el$3 = createElement("p");
    insertNode(_el$, _el$3);
    insert(_el$, createComponent2(Show, {
      get when() {
        return props.title;
      },
      get children() {
        var _el$2 = createElement("p");
        setProp(_el$2, "class", "text-sm");
        insert(_el$2, () => props.title);
        return _el$2;
      }
    }), _el$3);
    setProp(_el$3, "class", "text-sm text-muted-foreground");
    insert(_el$3, () => props.children);
    effect((_$p) => setProp(_el$, "class", computedClass(), _$p));
    return _el$;
  })();
};
// solid/components/badge.tsx
var badgeVariantClasses = {
  default: "bg-primary text-primary-foreground",
  secondary: "bg-secondary text-secondary-foreground",
  destructive: "bg-destructive text-destructive-foreground",
  outline: "bg-transparent text-foreground border border-border"
};
var Badge = (props) => {
  const merged = mergeProps({
    variant: "default"
  }, props);
  const computedClass = () => {
    const variant = badgeVariantClasses[merged.variant];
    return `inline-flex items-center rounded-full px-2 py-1 text-xs ${variant} ${props.class ?? ""}`;
  };
  return (() => {
    var _el$ = createElement("div"), _el$2 = createElement("p");
    insertNode(_el$, _el$2);
    insert(_el$2, () => props.children);
    effect((_$p) => setProp(_el$, "class", computedClass(), _$p));
    return _el$;
  })();
};
// solid/components/tag.tsx
var Tag = (props) => {
  const cls = props.class ?? props.className ?? "";
  return (() => {
    var _el$ = createElement("div"), _el$2 = createElement("p");
    insertNode(_el$, _el$2);
    setProp(_el$, "class", `inline-flex items-center rounded-md border border-border bg-muted px-2 py-1 text-xs text-muted-foreground ${cls}`);
    insert(_el$2, () => props.children);
    return _el$;
  })();
};
// solid/components/kbd.tsx
var Kbd = (props) => {
  const cls = props.class ?? props.className ?? "";
  return (() => {
    var _el$ = createElement("div"), _el$2 = createElement("p");
    insertNode(_el$, _el$2);
    setProp(_el$, "class", `inline-flex items-center rounded-md border border-border bg-muted px-2 py-1 text-xs font-mono text-foreground ${cls}`);
    insert(_el$2, () => props.children);
    return _el$;
  })();
};
// solid/components/progress.tsx
var Progress = (props) => {
  const merged = mergeProps({
    value: 0,
    max: 100
  }, props);
  const percentage = () => {
    const max = Number(merged.max);
    const value = Number(merged.value);
    if (!Number.isFinite(max) || max <= 0)
      return 0;
    if (!Number.isFinite(value))
      return 0;
    return Math.min(100, Math.max(0, value / max * 100));
  };
  const userClass = props.class ?? props.className ?? "";
  return (() => {
    var _el$ = createElement("div"), _el$2 = createElement("div");
    insertNode(_el$, _el$2);
    setProp(_el$, "class", `h-2 w-full overflow-hidden rounded-full bg-secondary ${userClass}`);
    setProp(_el$2, "class", "h-full bg-primary");
    effect((_$p) => setProp(_el$2, "style", {
      width: `${percentage()}%`
    }, _$p));
    return _el$;
  })();
};
// solid/components/pagination.tsx
var clampPaginationPage = (value, totalPages) => {
  if (!Number.isFinite(totalPages) || totalPages <= 0)
    return 1;
  const normalized = Number.isFinite(value) ? Math.floor(value) : 1;
  return Math.min(Math.floor(totalPages), Math.max(1, normalized));
};
var buildPaginationRange = (current, total, siblingCount) => {
  const totalPages = Math.max(1, Math.floor(total));
  const clampedCurrent = clampPaginationPage(current, totalPages);
  const count = Math.max(0, Math.floor(siblingCount));
  const totalPageNumbers = count * 2 + 5;
  if (totalPages <= totalPageNumbers) {
    return Array.from({
      length: totalPages
    }, (_, index) => index + 1);
  }
  const leftSiblingIndex = Math.max(clampedCurrent - count, 1);
  const rightSiblingIndex = Math.min(clampedCurrent + count, totalPages);
  const showLeftEllipsis = leftSiblingIndex > 2;
  const showRightEllipsis = rightSiblingIndex < totalPages - 1;
  if (!showLeftEllipsis && showRightEllipsis) {
    const leftItemCount = 3 + count * 2;
    return [...Array.from({
      length: leftItemCount
    }, (_, index) => index + 1), "ellipsis", totalPages];
  }
  if (showLeftEllipsis && !showRightEllipsis) {
    const rightItemCount = 3 + count * 2;
    const start = totalPages - rightItemCount + 1;
    return [1, "ellipsis", ...Array.from({
      length: rightItemCount
    }, (_, index) => start + index)];
  }
  return [1, "ellipsis", ...Array.from({
    length: rightSiblingIndex - leftSiblingIndex + 1
  }, (_, index) => leftSiblingIndex + index), "ellipsis", totalPages];
};
var Pagination = (props) => {
  const [local, others] = splitProps(props, ["page", "defaultPage", "totalPages", "siblingCount", "onChange", "class", "className"]);
  const [internalPage, setInternalPage] = createSignal(local.defaultPage ?? 1);
  const totalPages = () => {
    const total = Number(local.totalPages ?? 1);
    return Number.isFinite(total) && total > 0 ? Math.floor(total) : 1;
  };
  const currentPage = () => clampPaginationPage(local.page ?? internalPage(), totalPages());
  const siblingCount = () => {
    const count = Number(local.siblingCount ?? 1);
    return Number.isFinite(count) && count > 0 ? Math.floor(count) : 1;
  };
  const pageItems = createMemo(() => buildPaginationRange(currentPage(), totalPages(), siblingCount()));
  const setPage = (nextPage) => {
    const next = clampPaginationPage(nextPage, totalPages());
    if (next === currentPage())
      return;
    if (local.page === undefined) {
      setInternalPage(next);
    }
    local.onChange?.(next);
  };
  const buttonClass = (active, disabled) => {
    const base = "flex h-8 w-8 items-center justify-center rounded-md border border-border text-xs text-foreground";
    const state = active ? "bg-primary text-primary-foreground border-primary" : "";
    const disabledClass = disabled ? "opacity-50" : "";
    return [base, state, disabledClass].filter(Boolean).join(" ");
  };
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    return ["flex items-center gap-1", userClass].filter(Boolean).join(" ");
  };
  const canPrev = () => currentPage() > 1;
  const canNext = () => currentPage() < totalPages();
  return (() => {
    var _el$ = createElement("div"), _el$2 = createElement("button"), _el$3 = createElement("p"), _el$5 = createElement("button"), _el$6 = createElement("p");
    insertNode(_el$, _el$2);
    insertNode(_el$, _el$5);
    spread(_el$, mergeProps2({
      get ["class"]() {
        return computedClass();
      }
    }, others), true);
    insertNode(_el$2, _el$3);
    setProp(_el$2, "onClick", () => setPage(currentPage() - 1));
    setProp(_el$2, "ariaLabel", "Previous page");
    insertNode(_el$3, createTextNode(`\u2039`));
    setProp(_el$3, "class", "text-xs");
    insert(_el$, () => pageItems().map((item) => {
      if (item === "ellipsis") {
        return (() => {
          var _el$8 = createElement("p");
          insertNode(_el$8, createTextNode(`\u2026`));
          setProp(_el$8, "class", "px-2 text-xs text-muted-foreground");
          return _el$8;
        })();
      }
      const isActive = item === currentPage();
      return (() => {
        var _el$0 = createElement("button"), _el$1 = createElement("p");
        insertNode(_el$0, _el$1);
        setProp(_el$0, "onClick", () => setPage(item));
        setProp(_el$0, "ariaSelected", isActive);
        setProp(_el$0, "ariaLabel", `Page ${item}`);
        setProp(_el$1, "class", "text-xs");
        insert(_el$1, item);
        effect((_$p) => setProp(_el$0, "class", buttonClass(isActive, false), _$p));
        return _el$0;
      })();
    }), _el$5);
    insertNode(_el$5, _el$6);
    setProp(_el$5, "onClick", () => setPage(currentPage() + 1));
    setProp(_el$5, "ariaLabel", "Next page");
    insertNode(_el$6, createTextNode(`\u203A`));
    setProp(_el$6, "class", "text-xs");
    effect((_p$) => {
      var _v$ = buttonClass(false, !canPrev()), _v$2 = !canPrev(), _v$3 = !canPrev(), _v$4 = buttonClass(false, !canNext()), _v$5 = !canNext(), _v$6 = !canNext();
      _v$ !== _p$.e && (_p$.e = setProp(_el$2, "class", _v$, _p$.e));
      _v$2 !== _p$.t && (_p$.t = setProp(_el$2, "disabled", _v$2, _p$.t));
      _v$3 !== _p$.a && (_p$.a = setProp(_el$2, "ariaDisabled", _v$3, _p$.a));
      _v$4 !== _p$.o && (_p$.o = setProp(_el$5, "class", _v$4, _p$.o));
      _v$5 !== _p$.i && (_p$.i = setProp(_el$5, "disabled", _v$5, _p$.i));
      _v$6 !== _p$.n && (_p$.n = setProp(_el$5, "ariaDisabled", _v$6, _p$.n));
      return _p$;
    }, {
      e: undefined,
      t: undefined,
      a: undefined,
      o: undefined,
      i: undefined,
      n: undefined
    });
    return _el$;
  })();
};
// solid/components/stepper.tsx
var Stepper = (props) => {
  const [local, others] = splitProps(props, ["steps", "value", "defaultValue", "onChange", "orientation", "class", "className"]);
  const [internalValue, setInternalValue] = createSignal(local.defaultValue ?? 0);
  const steps = () => local.steps ?? [];
  const maxIndex = () => Math.max(0, steps().length - 1);
  const currentStep = () => {
    const raw = local.value ?? internalValue();
    const value = Number(raw);
    if (!Number.isFinite(value))
      return 0;
    return Math.min(maxIndex(), Math.max(0, Math.floor(value)));
  };
  const setCurrentStep = (value) => {
    const next = Math.min(maxIndex(), Math.max(0, Math.floor(Number.isFinite(value) ? value : 0)));
    if (next === currentStep())
      return;
    if (local.value === undefined) {
      setInternalValue(next);
    }
    local.onChange?.(next);
  };
  const orientation = () => local.orientation ?? "horizontal";
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    const base = orientation() === "vertical" ? "flex flex-col gap-3" : "flex flex-row items-center gap-3";
    return [base, userClass].filter(Boolean).join(" ");
  };
  const stepState = (index) => {
    if (index < currentStep())
      return "complete";
    if (index === currentStep())
      return "active";
    return "upcoming";
  };
  const indicatorClass = (state, disabled) => {
    const base = "flex h-7 w-7 items-center justify-center rounded-full border text-xs";
    const stateClass = state === "complete" ? "bg-primary text-primary-foreground border-primary" : state === "active" ? "border-primary text-foreground" : "border-border text-muted-foreground";
    const disabledClass = disabled ? "opacity-50" : "";
    return [base, stateClass, disabledClass].filter(Boolean).join(" ");
  };
  const titleClass = (state, disabled, align) => {
    const base = "text-sm";
    const stateClass = state === "upcoming" ? "text-muted-foreground" : "text-foreground";
    const disabledClass = disabled ? "opacity-50" : "";
    const alignClass = align === "center" ? "text-center" : "text-left";
    return [base, stateClass, disabledClass, alignClass].filter(Boolean).join(" ");
  };
  const descriptionClass = (disabled, align) => {
    const alignClass = align === "center" ? "text-center" : "text-left";
    const disabledClass = disabled ? "opacity-50" : "";
    return ["text-xs text-muted-foreground", alignClass, disabledClass].filter(Boolean).join(" ");
  };
  const stepButtonClass = (orientationValue, disabled) => {
    const base = orientationValue === "vertical" ? "flex flex-row items-start gap-3" : "flex flex-col items-center gap-1";
    const disabledClass = disabled ? "opacity-50" : "";
    return [base, disabledClass].filter(Boolean).join(" ");
  };
  if (steps().length === 0) {
    return null;
  }
  if (orientation() === "vertical") {
    return (() => {
      var _el$ = createElement("div");
      spread(_el$, mergeProps2({
        get ["class"]() {
          return computedClass();
        }
      }, others), true);
      insert(_el$, () => steps().map((step, index) => {
        const state = stepState(index);
        const disabled = Boolean(step.disabled);
        const isLast = index === steps().length - 1;
        return (() => {
          var _el$2 = createElement("button"), _el$3 = createElement("div"), _el$4 = createElement("div"), _el$6 = createElement("div"), _el$7 = createElement("p");
          insertNode(_el$2, _el$3);
          insertNode(_el$2, _el$6);
          setProp(_el$2, "onClick", () => {
            if (disabled)
              return;
            setCurrentStep(index);
          });
          setProp(_el$2, "disabled", disabled);
          setProp(_el$2, "ariaDisabled", disabled);
          setProp(_el$2, "ariaSelected", state === "active");
          insertNode(_el$3, _el$4);
          setProp(_el$3, "class", "flex flex-col items-center");
          insert(_el$4, state === "complete" ? "\u2713" : index + 1);
          insert(_el$3, createComponent2(Show, {
            when: !isLast,
            get children() {
              var _el$5 = createElement("div");
              setProp(_el$5, "class", "h-6 w-px bg-border");
              return _el$5;
            }
          }), null);
          insertNode(_el$6, _el$7);
          setProp(_el$6, "class", "flex flex-col gap-1");
          insert(_el$7, () => step.title);
          insert(_el$6, createComponent2(Show, {
            get when() {
              return step.description;
            },
            get children() {
              var _el$8 = createElement("p");
              insert(_el$8, () => step.description);
              effect((_$p) => setProp(_el$8, "class", descriptionClass(disabled, "left"), _$p));
              return _el$8;
            }
          }), null);
          effect((_p$) => {
            var _v$ = stepButtonClass("vertical", disabled), _v$2 = indicatorClass(state, disabled), _v$3 = titleClass(state, disabled, "left");
            _v$ !== _p$.e && (_p$.e = setProp(_el$2, "class", _v$, _p$.e));
            _v$2 !== _p$.t && (_p$.t = setProp(_el$4, "class", _v$2, _p$.t));
            _v$3 !== _p$.a && (_p$.a = setProp(_el$7, "class", _v$3, _p$.a));
            return _p$;
          }, {
            e: undefined,
            t: undefined,
            a: undefined
          });
          return _el$2;
        })();
      }));
      return _el$;
    })();
  }
  return (() => {
    var _el$9 = createElement("div");
    spread(_el$9, mergeProps2({
      get ["class"]() {
        return computedClass();
      }
    }, others), true);
    insert(_el$9, () => steps().map((step, index) => {
      const state = stepState(index);
      const disabled = Boolean(step.disabled);
      const isLast = index === steps().length - 1;
      return (() => {
        var _el$0 = createElement("div"), _el$1 = createElement("button"), _el$10 = createElement("div"), _el$11 = createElement("div"), _el$12 = createElement("p");
        insertNode(_el$0, _el$1);
        setProp(_el$0, "class", "flex flex-row items-center gap-3");
        insertNode(_el$1, _el$10);
        insertNode(_el$1, _el$11);
        setProp(_el$1, "onClick", () => {
          if (disabled)
            return;
          setCurrentStep(index);
        });
        setProp(_el$1, "disabled", disabled);
        setProp(_el$1, "ariaDisabled", disabled);
        setProp(_el$1, "ariaSelected", state === "active");
        insert(_el$10, state === "complete" ? "\u2713" : index + 1);
        insertNode(_el$11, _el$12);
        setProp(_el$11, "class", "flex flex-col items-center gap-1");
        insert(_el$12, () => step.title);
        insert(_el$11, createComponent2(Show, {
          get when() {
            return step.description;
          },
          get children() {
            var _el$13 = createElement("p");
            insert(_el$13, () => step.description);
            effect((_$p) => setProp(_el$13, "class", descriptionClass(disabled, "center"), _$p));
            return _el$13;
          }
        }), null);
        insert(_el$0, createComponent2(Show, {
          when: !isLast,
          get children() {
            var _el$14 = createElement("div");
            setProp(_el$14, "class", "h-px w-8 bg-border");
            return _el$14;
          }
        }), null);
        effect((_p$) => {
          var _v$4 = stepButtonClass("horizontal", disabled), _v$5 = indicatorClass(state, disabled), _v$6 = titleClass(state, disabled, "center");
          _v$4 !== _p$.e && (_p$.e = setProp(_el$1, "class", _v$4, _p$.e));
          _v$5 !== _p$.t && (_p$.t = setProp(_el$10, "class", _v$5, _p$.t));
          _v$6 !== _p$.a && (_p$.a = setProp(_el$12, "class", _v$6, _p$.a));
          return _p$;
        }, {
          e: undefined,
          t: undefined,
          a: undefined
        });
        return _el$0;
      })();
    }));
    return _el$9;
  })();
};
// solid/components/tabs.tsx
var TabsContext = createContext();
var useTabsContext = () => {
  const ctx = useContext(TabsContext);
  if (!ctx) {
    throw new Error("Tabs components must be used within a <Tabs> container");
  }
  return ctx;
};
var Tabs = (props) => {
  const [local, others] = splitProps(props, ["value", "defaultValue", "onChange", "orientation", "class", "className", "children"]);
  const [internalValue, setInternalValue] = createSignal(local.defaultValue);
  const isControlled = () => local.value !== undefined;
  const currentValue = () => isControlled() ? local.value : internalValue();
  const setValue = (value) => {
    if (!isControlled()) {
      setInternalValue(value);
    }
    local.onChange?.(value);
  };
  const orientation = () => local.orientation ?? "horizontal";
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    return ["flex flex-col gap-2", userClass].filter(Boolean).join(" ");
  };
  return createComponent2(TabsContext.Provider, {
    value: {
      value: currentValue,
      setValue,
      orientation,
      isControlled
    },
    get children() {
      var _el$ = createElement("div");
      spread(_el$, mergeProps2({
        get ["class"]() {
          return computedClass();
        }
      }, others), true);
      insert(_el$, () => local.children);
      return _el$;
    }
  });
};
var TabsList = (props) => {
  const ctx = useTabsContext();
  const [local, others] = splitProps(props, ["class", "className", "children"]);
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    const base = ctx.orientation() === "vertical" ? "flex flex-col gap-1 rounded-md bg-muted p-1" : "flex flex-row gap-1 rounded-md bg-muted p-1";
    return [base, userClass].filter(Boolean).join(" ");
  };
  return (() => {
    var _el$2 = createElement("div");
    setProp(_el$2, "role", "tablist");
    setProp(_el$2, "roving", true);
    spread(_el$2, mergeProps2({
      get ["class"]() {
        return computedClass();
      }
    }, others), true);
    insert(_el$2, () => local.children);
    return _el$2;
  })();
};
var TabsTrigger = (props) => {
  const ctx = useTabsContext();
  const [local, others] = splitProps(props, ["value", "class", "className", "disabled", "children", "onClick", "onFocus"]);
  const isActive = () => ctx.value() === local.value;
  createEffect(() => {
    if (!ctx.isControlled() && ctx.value() == null) {
      ctx.setValue(local.value);
    }
  });
  const handleActivate = (event) => {
    if (local.disabled)
      return;
    ctx.setValue(local.value);
    return event;
  };
  const handleClick = (event) => {
    handleActivate(event);
    local.onClick?.(event);
  };
  const handleFocus = (event) => {
    handleActivate(event);
    local.onFocus?.(event);
  };
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    const base = "inline-flex items-center justify-center rounded-md px-3 py-1.5 text-sm";
    const stateClass = isActive() ? "bg-background text-foreground" : "text-muted-foreground hover:bg-accent hover:text-accent-foreground";
    const disabled = local.disabled ? "opacity-50" : "";
    return [base, stateClass, disabled, userClass].filter(Boolean).join(" ");
  };
  return (() => {
    var _el$3 = createElement("button");
    setProp(_el$3, "role", "tab");
    setProp(_el$3, "onClick", handleClick);
    setProp(_el$3, "onFocus", handleFocus);
    spread(_el$3, mergeProps2({
      get ["class"]() {
        return computedClass();
      },
      get ariaSelected() {
        return isActive();
      },
      get ariaDisabled() {
        return local.disabled;
      },
      get disabled() {
        return local.disabled;
      }
    }, others), true);
    insert(_el$3, () => local.children);
    return _el$3;
  })();
};
var TabsContent = (props) => {
  const ctx = useTabsContext();
  const [local, others] = splitProps(props, ["value", "forceMount", "class", "className", "children"]);
  const isActive = () => ctx.value() === local.value;
  const computedClass = (hidden = false) => {
    const userClass = local.class ?? local.className ?? "";
    const base = "rounded-md border border-border p-4";
    return [base, hidden ? "hidden" : "", userClass].filter(Boolean).join(" ");
  };
  if (local.forceMount) {
    return (() => {
      var _el$4 = createElement("div");
      setProp(_el$4, "role", "tabpanel");
      spread(_el$4, mergeProps2({
        get ["class"]() {
          return computedClass(!isActive());
        },
        get ariaHidden() {
          return !isActive();
        }
      }, others), true);
      insert(_el$4, () => local.children);
      return _el$4;
    })();
  }
  return createComponent2(Show, {
    get when() {
      return isActive();
    },
    get children() {
      var _el$5 = createElement("div");
      setProp(_el$5, "role", "tabpanel");
      setProp(_el$5, "ariaHidden", false);
      spread(_el$5, mergeProps2({
        get ["class"]() {
          return computedClass(false);
        }
      }, others), true);
      insert(_el$5, () => local.children);
      return _el$5;
    }
  });
};
// solid/components/group-box.tsx
var GroupBox = (props) => {
  const [local, others] = splitProps(props, ["title", "description", "class", "className", "children"]);
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    return ["flex flex-col gap-3 rounded-md border border-border p-4", userClass].filter(Boolean).join(" ");
  };
  const headerClass = () => "flex flex-col gap-1";
  return (() => {
    var _el$ = createElement("div");
    spread(_el$, mergeProps2({
      get ["class"]() {
        return computedClass();
      }
    }, others), true);
    insert(_el$, createComponent2(Show, {
      get when() {
        return local.title || local.description;
      },
      get children() {
        var _el$2 = createElement("div");
        insert(_el$2, createComponent2(Show, {
          get when() {
            return local.title;
          },
          get children() {
            var _el$3 = createElement("p");
            setProp(_el$3, "class", "text-sm text-foreground");
            insert(_el$3, () => local.title);
            return _el$3;
          }
        }), null);
        insert(_el$2, createComponent2(Show, {
          get when() {
            return local.description;
          },
          get children() {
            var _el$4 = createElement("p");
            setProp(_el$4, "class", "text-xs text-muted-foreground");
            insert(_el$4, () => local.description);
            return _el$4;
          }
        }), null);
        effect((_$p) => setProp(_el$2, "class", headerClass(), _$p));
        return _el$2;
      }
    }), null);
    insert(_el$, () => local.children, null);
    return _el$;
  })();
};
// solid/components/description-list.tsx
var DescriptionList = (props) => {
  const [local, others] = splitProps(props, ["items", "class", "className", "itemClass", "termClass", "descriptionClass", "children"]);
  const listClass = () => {
    const userClass = local.class ?? local.className ?? "";
    return ["flex flex-col gap-3", userClass].filter(Boolean).join(" ");
  };
  const itemClass = () => {
    const userClass = local.itemClass ?? "";
    return ["flex flex-col gap-1", userClass].filter(Boolean).join(" ");
  };
  const termClass = () => {
    const userClass = local.termClass ?? "";
    return ["text-xs text-muted-foreground", userClass].filter(Boolean).join(" ");
  };
  const descriptionClass = () => {
    const userClass = local.descriptionClass ?? "";
    return ["text-sm text-foreground", userClass].filter(Boolean).join(" ");
  };
  const renderItems = () => local.items?.map((item) => (() => {
    var _el$ = createElement("div"), _el$2 = createElement("p"), _el$3 = createElement("p");
    insertNode(_el$, _el$2);
    insertNode(_el$, _el$3);
    insert(_el$2, () => item.term);
    insert(_el$3, () => item.description);
    effect((_p$) => {
      var _v$ = itemClass(), _v$2 = termClass(), _v$3 = descriptionClass();
      _v$ !== _p$.e && (_p$.e = setProp(_el$, "class", _v$, _p$.e));
      _v$2 !== _p$.t && (_p$.t = setProp(_el$2, "class", _v$2, _p$.t));
      _v$3 !== _p$.a && (_p$.a = setProp(_el$3, "class", _v$3, _p$.a));
      return _p$;
    }, {
      e: undefined,
      t: undefined,
      a: undefined
    });
    return _el$;
  })());
  return (() => {
    var _el$4 = createElement("div");
    spread(_el$4, mergeProps2({
      get ["class"]() {
        return listClass();
      }
    }, others), true);
    insert(_el$4, (() => {
      var _c$ = memo2(() => !!(local.items && local.items.length > 0));
      return () => _c$() ? renderItems() : local.children;
    })());
    return _el$4;
  })();
};
// solid/components/separator.tsx
var Separator = (props) => {
  const isHorizontal = () => (props.orientation ?? "horizontal") === "horizontal";
  const separatorClass = () => {
    if (isHorizontal()) {
      return `h-px w-full bg-border ${props.class ?? ""}`;
    }
    return `h-full w-px bg-border ${props.class ?? ""}`;
  };
  return (() => {
    var _el$ = createElement("div");
    effect((_$p) => setProp(_el$, "class", separatorClass(), _$p));
    return _el$;
  })();
};
// solid/components/switch.tsx
var Switch = (props) => {
  const [local, others] = splitProps(props, ["checked", "defaultChecked", "onChange", "disabled", "class", "className", "role", "ariaLabel", "onClick"]);
  const [internalChecked, setInternalChecked] = createSignal(local.defaultChecked ?? false);
  const isChecked = () => local.checked !== undefined ? local.checked : internalChecked();
  const handleClick = (event) => {
    if (local.disabled)
      return;
    const newValue = !isChecked();
    if (local.checked === undefined) {
      setInternalChecked(newValue);
    }
    local.onChange?.(newValue);
    local.onClick?.(event);
  };
  const trackClass = () => {
    const userClass = local.class ?? local.className ?? "";
    const base = isChecked() ? "bg-primary" : "bg-input";
    const disabled = local.disabled ? "opacity-50" : "";
    return ["flex flex-row items-center h-6 w-11 rounded-full", base, disabled, userClass].filter(Boolean).join(" ");
  };
  const thumbClass = () => {
    return "h-5 w-5 rounded-full bg-white";
  };
  const spacerClass = () => {
    return isChecked() ? "w-5" : "w-px";
  };
  return (() => {
    var _el$ = createElement("button"), _el$2 = createElement("div"), _el$4 = createElement("div");
    insertNode(_el$, _el$2);
    insertNode(_el$, _el$4);
    setProp(_el$, "onClick", handleClick);
    spread(_el$, mergeProps2({
      get ["class"]() {
        return trackClass();
      },
      get disabled() {
        return local.disabled;
      },
      get role() {
        return local.role ?? "switch";
      },
      get ariaChecked() {
        return isChecked();
      },
      get ariaDisabled() {
        return local.disabled;
      },
      get ariaLabel() {
        return local.ariaLabel;
      }
    }, others), true);
    insertNode(_el$2, createTextNode(` `));
    insertNode(_el$4, createTextNode(` `));
    effect((_p$) => {
      var _v$ = spacerClass(), _v$2 = thumbClass();
      _v$ !== _p$.e && (_p$.e = setProp(_el$2, "class", _v$, _p$.e));
      _v$2 !== _p$.t && (_p$.t = setProp(_el$4, "class", _v$2, _p$.t));
      return _p$;
    }, {
      e: undefined,
      t: undefined
    });
    return _el$;
  })();
};
// solid/components/toggle.tsx
var Toggle = (props) => {
  const [local, others] = splitProps(props, ["pressed", "defaultPressed", "onChange", "disabled", "class", "className", "role", "ariaLabel", "children", "onClick"]);
  const [internalPressed, setInternalPressed] = createSignal(local.defaultPressed ?? false);
  const isPressed = () => local.pressed !== undefined ? local.pressed : internalPressed();
  const handleClick = (event) => {
    if (local.disabled)
      return;
    const nextValue = !isPressed();
    if (local.pressed === undefined) {
      setInternalPressed(nextValue);
    }
    local.onChange?.(nextValue);
    local.onClick?.(event);
  };
  const toggleClass = () => {
    const userClass = local.class ?? local.className ?? "";
    const base = "inline-flex items-center justify-center rounded-md border px-3 py-1 text-sm";
    const state = isPressed() ? "bg-primary text-primary-foreground border-primary" : "bg-transparent text-foreground border-input";
    const disabled = local.disabled ? "opacity-50" : "";
    return [base, state, disabled, userClass].filter(Boolean).join(" ");
  };
  return (() => {
    var _el$ = createElement("button");
    setProp(_el$, "onClick", handleClick);
    spread(_el$, mergeProps2({
      get ["class"]() {
        return toggleClass();
      },
      get disabled() {
        return local.disabled;
      },
      get role() {
        return local.role ?? "button";
      },
      get ariaPressed() {
        return isPressed();
      },
      get ariaDisabled() {
        return local.disabled;
      },
      get ariaLabel() {
        return local.ariaLabel;
      }
    }, others), true);
    insert(_el$, () => local.children);
    return _el$;
  })();
};
// solid/components/skeleton.tsx
var Skeleton = (props) => {
  const cls = props.class ?? props.className ?? "";
  return (() => {
    var _el$ = createElement("div");
    setProp(_el$, "class", `bg-muted rounded-md ${cls}`);
    return _el$;
  })();
};
// solid/components/textarea.tsx
var Textarea = (props) => {
  const [localValue, setLocalValue] = createSignal(props.value ?? "");
  const displayValue = () => props.value !== undefined ? props.value : localValue();
  const handleInput = (e) => {
    let newValue;
    if (e?.target?.value !== undefined) {
      newValue = e.target.value;
    } else if (e?.detail !== undefined) {
      newValue = e.detail;
    } else if (e instanceof Uint8Array) {
      newValue = new TextDecoder().decode(e);
    } else {
      newValue = String(e ?? "");
    }
    setLocalValue(newValue);
    props.onChange?.(newValue);
  };
  const computedClass = () => {
    const disabled = props.disabled ? "opacity-50" : "";
    return `flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground ${disabled} ${props.class ?? ""}`;
  };
  return (() => {
    var _el$ = createElement("textarea");
    setProp(_el$, "onInput", handleInput);
    effect((_p$) => {
      var _v$ = computedClass(), _v$2 = displayValue(), _v$3 = props.placeholder, _v$4 = props.rows ?? 3, _v$5 = props.disabled;
      _v$ !== _p$.e && (_p$.e = setProp(_el$, "class", _v$, _p$.e));
      _v$2 !== _p$.t && (_p$.t = setProp(_el$, "value", _v$2, _p$.t));
      _v$3 !== _p$.a && (_p$.a = setProp(_el$, "placeholder", _v$3, _p$.a));
      _v$4 !== _p$.o && (_p$.o = setProp(_el$, "rows", _v$4, _p$.o));
      _v$5 !== _p$.i && (_p$.i = setProp(_el$, "disabled", _v$5, _p$.i));
      return _p$;
    }, {
      e: undefined,
      t: undefined,
      a: undefined,
      o: undefined,
      i: undefined
    });
    return _el$;
  })();
};
// solid/components/scrollable.tsx
var Scrollable = (props) => {
  const [local, others] = splitProps(props, ["class", "className", "scrollX", "scrollY", "canvasWidth", "canvasHeight", "autoCanvas", "onScroll", "children"]);
  const computedClass = () => {
    const userClass = local.class ?? local.className ?? "";
    return ["overflow-hidden", userClass].filter(Boolean).join(" ");
  };
  return (() => {
    var _el$ = createElement("div");
    setProp(_el$, "scroll", true);
    spread(_el$, mergeProps2({
      get ["class"]() {
        return computedClass();
      },
      get scrollX() {
        return local.scrollX;
      },
      get scrollY() {
        return local.scrollY;
      },
      get canvasWidth() {
        return local.canvasWidth;
      },
      get canvasHeight() {
        return local.canvasHeight;
      },
      get autoCanvas() {
        return local.autoCanvas ?? true;
      },
      get onScroll() {
        return local.onScroll;
      }
    }, others), true);
    insert(_el$, () => local.children);
    return _el$;
  })();
};
// solid/components/list.tsx
var decodeScrollPayload = (payload) => {
  if (!payload || payload.length === 0)
    return "";
  return new TextDecoder().decode(payload);
};
var List = (props) => {
  const [scrollDetail, setScrollDetail] = createSignal(null);
  const items = () => props.items ?? [];
  const itemCount = () => items().length;
  const itemSize = () => {
    const value = Number(props.itemSize ?? 0);
    return Number.isFinite(value) ? value : 0;
  };
  const isVirtual = () => Boolean(props.virtual) && itemSize() > 0;
  const virtualRange = createMemo(() => {
    const total = itemCount();
    if (!isVirtual()) {
      return {
        start: 0,
        end: total,
        offset: 0
      };
    }
    const detail = scrollDetail();
    const viewportSize = detail?.viewportHeight ?? props.viewportHeight ?? 0;
    if (!Number.isFinite(viewportSize) || viewportSize <= 0) {
      return {
        start: 0,
        end: total,
        offset: 0
      };
    }
    return computeVirtualRange({
      itemCount: total,
      itemSize: itemSize(),
      viewportSize,
      scrollOffset: detail?.offsetY ?? 0,
      overscan: props.overscan
    });
  });
  const visibleItems = createMemo(() => {
    const all = items();
    if (!isVirtual())
      return all;
    const range = virtualRange();
    return all.slice(range.start, range.end);
  });
  const totalHeight = createMemo(() => {
    if (typeof props.canvasHeight === "number" && Number.isFinite(props.canvasHeight)) {
      return props.canvasHeight;
    }
    if (isVirtual()) {
      return itemCount() * itemSize();
    }
    return;
  });
  const contentClass = () => {
    const userClass = props.contentClass ?? props.contentClassName ?? "";
    return ["flex flex-col", userClass].filter(Boolean).join(" ");
  };
  const itemClass = () => props.itemClass ?? props.itemClassName ?? "";
  const offsetStyle = () => {
    if (!isVirtual())
      return;
    return {
      transform: `translateY(${virtualRange().offset}px)`
    };
  };
  const itemStyle = () => {
    if (!isVirtual())
      return;
    const size = itemSize();
    if (!size)
      return;
    return {
      height: `${size}px`
    };
  };
  const handleScroll = (payload) => {
    const detail = parseScrollDetail(decodeScrollPayload(payload));
    if (detail) {
      setScrollDetail(detail);
    }
    if (typeof props.onScroll === "function") {
      props.onScroll(payload);
    }
  };
  const renderItem = (item, index) => {
    if (typeof props.renderItem === "function") {
      return props.renderItem(item, index);
    }
    return item;
  };
  const renderedItems = () => {
    const range = virtualRange();
    return visibleItems().map((item, index) => {
      const realIndex = isVirtual() ? range.start + index : index;
      return (() => {
        var _el$ = createElement("div");
        insert(_el$, () => renderItem(item, realIndex));
        effect((_p$) => {
          var _v$ = itemClass(), _v$2 = itemStyle();
          _v$ !== _p$.e && (_p$.e = setProp(_el$, "class", _v$, _p$.e));
          _v$2 !== _p$.t && (_p$.t = setProp(_el$, "style", _v$2, _p$.t));
          return _p$;
        }, {
          e: undefined,
          t: undefined
        });
        return _el$;
      })();
    });
  };
  const listClass = () => props.class ?? props.className ?? "";
  const autoCanvas = () => props.autoCanvas ?? !isVirtual();
  return createComponent2(Scrollable, {
    get ["class"]() {
      return listClass();
    },
    get scrollX() {
      return props.scrollX;
    },
    get scrollY() {
      return props.scrollY;
    },
    get canvasWidth() {
      return props.canvasWidth;
    },
    get canvasHeight() {
      return totalHeight();
    },
    get autoCanvas() {
      return autoCanvas();
    },
    onScroll: handleScroll,
    get children() {
      var _el$2 = createElement("div");
      insert(_el$2, renderedItems);
      effect((_p$) => {
        var _v$3 = contentClass(), _v$4 = offsetStyle();
        _v$3 !== _p$.e && (_p$.e = setProp(_el$2, "class", _v$3, _p$.e));
        _v$4 !== _p$.t && (_p$.t = setProp(_el$2, "style", _v$4, _p$.t));
        return _p$;
      }, {
        e: undefined,
        t: undefined
      });
      return _el$2;
    }
  });
};
// solid/App.tsx
var App = () => {
  const [lastEvent, setLastEvent] = createSignal("None");
  const [scrollDetail, setScrollDetail] = createSignal("Idle");
  const [dragDetail, setDragDetail] = createSignal("Idle");
  const [overlayOpen, setOverlayOpen] = createSignal(false);
  const [activeTab, setActiveTab] = createSignal("account");
  const [activePage, setActivePage] = createSignal(3);
  const [activeStep, setActiveStep] = createSignal(1);
  const [activeRadio, setActiveRadio] = createSignal("email");
  const [togglePressed, setTogglePressed] = createSignal(false);
  const formatPointerDetail = (detail) => {
    const x = detail.x;
    const y = detail.y;
    if (typeof x !== "number" || typeof y !== "number")
      return "";
    const button2 = typeof detail.button === "number" ? detail.button : 0;
    const modifiers = typeof detail.modifiers === "number" ? detail.modifiers : 0;
    return `x=${x.toFixed(1)} y=${y.toFixed(1)} btn=${button2} mod=${modifiers}`;
  };
  const decodePayload = (payload) => {
    if (payload == null)
      return "";
    if (typeof payload === "string")
      return payload;
    if (typeof payload === "object") {
      const detailValue = payload;
      const pointerFormatted = formatPointerDetail(detailValue);
      if (pointerFormatted)
        return pointerFormatted;
    }
    if (payload instanceof ArrayBuffer) {
      if (payload.byteLength === 0)
        return "";
      return new TextDecoder().decode(new Uint8Array(payload));
    }
    if (ArrayBuffer.isView(payload)) {
      const view = payload;
      if (view.byteLength === 0)
        return "";
      return new TextDecoder().decode(new Uint8Array(view.buffer, view.byteOffset, view.byteLength));
    }
    if (typeof payload === "object") {
      const record = payload;
      if (typeof record.detail === "string")
        return record.detail;
      if (record.detail && typeof record.detail === "object") {
        const formatted = formatPointerDetail(record.detail);
        if (formatted)
          return formatted;
        return "";
      }
      if (record.detail != null)
        return String(record.detail);
      if (typeof record.key === "string")
        return record.key;
      const target = record.target;
      if (target?.value != null)
        return String(target.value);
      return "";
    }
    return String(payload);
  };
  const logEvent = (label2) => (payload) => {
    const detail = decodePayload(payload);
    setLastEvent(detail ? `${label2}: ${detail}` : label2);
  };
  const logScroll = (payload) => {
    const detail = decodePayload(payload) || "Idle";
    setScrollDetail(detail);
    setLastEvent(detail === "Idle" ? "scroll" : `scroll: ${detail}`);
  };
  const logDrag = (label2) => (payload) => {
    const detail = decodePayload(payload);
    const message = detail ? `${label2}: ${detail}` : label2;
    setDragDetail(message);
    setLastEvent(message);
  };
  const listItemHeight = 32;
  const listViewportHeight = 160;
  const scrollItems = Array.from({
    length: 60
  }, (_, index) => `Row ${index + 1}`);
  const stepItems = [{
    title: "Profile",
    description: "Basics"
  }, {
    title: "Plan",
    description: "Billing"
  }, {
    title: "Confirm",
    description: "Review"
  }];
  return (() => {
    var _el$ = createElement("div"), _el$2 = createElement("div"), _el$3 = createElement("h1"), _el$5 = createElement("p"), _el$7 = createElement("div"), _el$8 = createElement("div"), _el$9 = createElement("div"), _el$0 = createElement("div"), _el$1 = createElement("h2"), _el$11 = createElement("p"), _el$12 = createTextNode(`Last event: `), _el$13 = createElement("div"), _el$14 = createElement("p"), _el$16 = createElement("input"), _el$17 = createElement("div"), _el$18 = createElement("div"), _el$19 = createElement("div"), _el$20 = createElement("div"), _el$21 = createElement("h2"), _el$23 = createElement("p"), _el$24 = createElement("div"), _el$25 = createElement("div"), _el$26 = createElement("p"), _el$28 = createElement("div"), _el$30 = createElement("div"), _el$31 = createElement("p"), _el$33 = createElement("div"), _el$35 = createElement("div"), _el$36 = createElement("h2"), _el$38 = createElement("div"), _el$39 = createElement("div"), _el$40 = createElement("p"), _el$42 = createElement("div"), _el$43 = createElement("p"), _el$44 = createElement("div"), _el$45 = createElement("div"), _el$46 = createElement("h2"), _el$48 = createElement("p"), _el$49 = createTextNode(`Active tab: `), _el$56 = createElement("div"), _el$57 = createElement("h2"), _el$60 = createElement("div"), _el$61 = createElement("div"), _el$62 = createElement("div"), _el$63 = createElement("h2"), _el$65 = createElement("p"), _el$66 = createElement("div"), _el$67 = createElement("h2"), _el$69 = createElement("p"), _el$71 = createElement("div"), _el$72 = createElement("h2"), _el$74 = createElement("div"), _el$75 = createElement("div"), _el$76 = createElement("div"), _el$77 = createElement("p"), _el$79 = createElement("div");
    insertNode(_el$, _el$2);
    insertNode(_el$, _el$7);
    setProp(_el$, "class", "flex flex-col gap-6 p-6");
    insertNode(_el$2, _el$3);
    insertNode(_el$2, _el$5);
    setProp(_el$2, "class", "flex flex-col gap-1");
    insertNode(_el$3, createTextNode(`Component Harness`));
    setProp(_el$3, "class", "text-lg text-foreground");
    insertNode(_el$5, createTextNode(`Validate overlays, focus/keyboard routing, drag, and scroll behaviors.`));
    setProp(_el$5, "class", "text-sm text-muted-foreground");
    insertNode(_el$7, _el$8);
    insertNode(_el$7, _el$60);
    setProp(_el$7, "class", "flex flex-row gap-6");
    insertNode(_el$8, _el$9);
    insertNode(_el$8, _el$19);
    insertNode(_el$8, _el$35);
    insertNode(_el$8, _el$44);
    insertNode(_el$8, _el$56);
    setProp(_el$8, "class", "flex flex-col gap-6");
    insertNode(_el$9, _el$0);
    insertNode(_el$9, _el$13);
    insertNode(_el$9, _el$18);
    setProp(_el$9, "class", "flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96");
    insertNode(_el$0, _el$1);
    insertNode(_el$0, _el$11);
    setProp(_el$0, "class", "flex flex-col gap-1");
    insertNode(_el$1, createTextNode(`Focus + Keyboard`));
    setProp(_el$1, "class", "text-sm text-foreground");
    insertNode(_el$11, _el$12);
    setProp(_el$11, "class", "text-xs text-muted-foreground");
    insert(_el$11, lastEvent, null);
    insertNode(_el$13, _el$14);
    insertNode(_el$13, _el$16);
    insertNode(_el$13, _el$17);
    setProp(_el$13, "focusTrap", true);
    setProp(_el$13, "class", "flex flex-col gap-3 rounded-md border border-border p-3");
    insertNode(_el$14, createTextNode(`Focus trap region`));
    setProp(_el$14, "class", "text-xs text-muted-foreground");
    setProp(_el$16, "class", "h-10 rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground");
    setProp(_el$16, "placeholder", "Focusable input");
    setProp(_el$17, "class", "flex flex-row gap-2");
    insert(_el$17, createComponent2(Button, {
      size: "sm",
      get onClick() {
        return logEvent("click");
      },
      children: "Primary"
    }), null);
    insert(_el$17, createComponent2(Button, {
      size: "sm",
      variant: "outline",
      get onClick() {
        return logEvent("click");
      },
      children: "Outline"
    }), null);
    setProp(_el$18, "roving", true);
    setProp(_el$18, "class", "flex flex-row gap-2 rounded-md border border-border p-2");
    insert(_el$18, createComponent2(Button, {
      size: "sm",
      tabIndex: 0,
      get onFocus() {
        return logEvent("roving focus");
      },
      children: "One"
    }), null);
    insert(_el$18, createComponent2(Button, {
      size: "sm",
      tabIndex: 0,
      get onFocus() {
        return logEvent("roving focus");
      },
      children: "Two"
    }), null);
    insert(_el$18, createComponent2(Button, {
      size: "sm",
      tabIndex: 0,
      get onFocus() {
        return logEvent("roving focus");
      },
      children: "Three"
    }), null);
    insertNode(_el$19, _el$20);
    insertNode(_el$19, _el$24);
    setProp(_el$19, "class", "flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96");
    insertNode(_el$20, _el$21);
    insertNode(_el$20, _el$23);
    setProp(_el$20, "class", "flex flex-col gap-1");
    insertNode(_el$21, createTextNode(`Drag + Drop`));
    setProp(_el$21, "class", "text-sm text-foreground");
    setProp(_el$23, "class", "text-xs text-muted-foreground");
    insert(_el$23, dragDetail);
    insertNode(_el$24, _el$25);
    insertNode(_el$24, _el$30);
    setProp(_el$24, "class", "flex flex-row gap-4");
    insertNode(_el$25, _el$26);
    insertNode(_el$25, _el$28);
    setProp(_el$25, "class", "flex flex-col gap-2 rounded-md border border-border p-3 w-44");
    insertNode(_el$26, createTextNode(`Drag source`));
    setProp(_el$26, "class", "text-xs text-muted-foreground");
    insertNode(_el$28, createTextNode(`Drag me`));
    setProp(_el$28, "class", "flex h-10 items-center justify-center rounded-md bg-primary text-primary-foreground");
    insertNode(_el$30, _el$31);
    insertNode(_el$30, _el$33);
    setProp(_el$30, "class", "flex flex-col gap-2 rounded-md border border-border p-3 w-44");
    insertNode(_el$31, createTextNode(`Drop target`));
    setProp(_el$31, "class", "text-xs text-muted-foreground");
    insertNode(_el$33, createTextNode(`Drop here`));
    setProp(_el$33, "class", "flex h-10 items-center justify-center rounded-md bg-muted text-muted-foreground");
    insertNode(_el$35, _el$36);
    insertNode(_el$35, _el$38);
    setProp(_el$35, "class", "flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96");
    insertNode(_el$36, createTextNode(`Inputs + Toggles`));
    setProp(_el$36, "class", "text-sm text-foreground");
    insertNode(_el$38, _el$39);
    insertNode(_el$38, _el$42);
    setProp(_el$38, "class", "flex flex-col gap-3");
    insert(_el$38, createComponent2(Checkbox, {
      label: "Receive updates"
    }), _el$39);
    insert(_el$38, createComponent2(RadioGroup, {
      get value() {
        return activeRadio();
      },
      onChange: setActiveRadio,
      get children() {
        return [createComponent2(Radio, {
          value: "email",
          label: "Email alerts"
        }), createComponent2(Radio, {
          value: "sms",
          label: "SMS alerts"
        })];
      }
    }), _el$39);
    insertNode(_el$39, _el$40);
    setProp(_el$39, "class", "flex flex-row items-center gap-3");
    insert(_el$39, createComponent2(Switch, {}), _el$40);
    insertNode(_el$40, createTextNode(`Enable preview`));
    setProp(_el$40, "class", "text-sm text-muted-foreground");
    insertNode(_el$42, _el$43);
    setProp(_el$42, "class", "flex flex-row items-center gap-3");
    insert(_el$42, createComponent2(Toggle, {
      get pressed() {
        return togglePressed();
      },
      onChange: setTogglePressed,
      children: "Auto-save"
    }), _el$43);
    setProp(_el$43, "class", "text-xs text-muted-foreground");
    insert(_el$43, () => togglePressed() ? "On" : "Off");
    insert(_el$38, createComponent2(Textarea, {
      placeholder: "Type notes...",
      rows: 3
    }), null);
    insertNode(_el$44, _el$45);
    setProp(_el$44, "class", "flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96");
    insertNode(_el$45, _el$46);
    insertNode(_el$45, _el$48);
    setProp(_el$45, "class", "flex flex-col gap-1");
    insertNode(_el$46, createTextNode(`Tabs`));
    setProp(_el$46, "class", "text-sm text-foreground");
    insertNode(_el$48, _el$49);
    setProp(_el$48, "class", "text-xs text-muted-foreground");
    insert(_el$48, activeTab, null);
    insert(_el$44, createComponent2(Tabs, {
      get value() {
        return activeTab();
      },
      onChange: setActiveTab,
      class: "flex flex-col gap-3",
      get children() {
        return [createComponent2(TabsList, {
          get children() {
            return [createComponent2(TabsTrigger, {
              value: "account",
              children: "Account"
            }), createComponent2(TabsTrigger, {
              value: "billing",
              children: "Billing"
            }), createComponent2(TabsTrigger, {
              value: "team",
              children: "Team"
            })];
          }
        }), createComponent2(TabsContent, {
          value: "account",
          get children() {
            var _el$50 = createElement("p");
            insertNode(_el$50, createTextNode(`Manage profile and password.`));
            setProp(_el$50, "class", "text-sm text-muted-foreground");
            return _el$50;
          }
        }), createComponent2(TabsContent, {
          value: "billing",
          get children() {
            var _el$52 = createElement("p");
            insertNode(_el$52, createTextNode(`Update payment details.`));
            setProp(_el$52, "class", "text-sm text-muted-foreground");
            return _el$52;
          }
        }), createComponent2(TabsContent, {
          value: "team",
          get children() {
            var _el$54 = createElement("p");
            insertNode(_el$54, createTextNode(`Invite collaborators.`));
            setProp(_el$54, "class", "text-sm text-muted-foreground");
            return _el$54;
          }
        })];
      }
    }), null);
    insertNode(_el$56, _el$57);
    setProp(_el$56, "class", "flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96");
    insertNode(_el$57, createTextNode(`Actions + Containers`));
    setProp(_el$57, "class", "text-sm text-foreground");
    insert(_el$56, createComponent2(GroupBox, {
      title: "Team Access",
      description: "Manage roles and visibility.",
      get children() {
        var _el$59 = createElement("div");
        setProp(_el$59, "class", "flex flex-row gap-2");
        insert(_el$59, createComponent2(Button, {
          size: "sm",
          children: "Invite"
        }), null);
        insert(_el$59, createComponent2(Button, {
          size: "sm",
          variant: "secondary",
          children: "Settings"
        }), null);
        return _el$59;
      }
    }), null);
    insert(_el$56, createComponent2(Accordion, {
      type: "single",
      defaultValue: "overview",
      collapsible: true,
      get children() {
        return [createComponent2(AccordionItem, {
          value: "overview",
          get children() {
            return [createComponent2(AccordionTrigger, {
              children: "Overview"
            }), createComponent2(AccordionContent, {
              children: "Quick status and usage details."
            })];
          }
        }), createComponent2(AccordionItem, {
          value: "details",
          get children() {
            return [createComponent2(AccordionTrigger, {
              children: "Details"
            }), createComponent2(AccordionContent, {
              children: "Additional configuration and metadata."
            })];
          }
        })];
      }
    }), null);
    insert(_el$56, createComponent2(Collapsible, {
      defaultOpen: true,
      get children() {
        return [createComponent2(CollapsibleTrigger, {
          class: "rounded-md bg-muted px-2 py-1",
          children: "Notes"
        }), createComponent2(CollapsibleContent, {
          children: "Use collapsible panels for optional helper copy."
        })];
      }
    }), null);
    insertNode(_el$60, _el$61);
    insertNode(_el$60, _el$66);
    insertNode(_el$60, _el$71);
    setProp(_el$60, "class", "flex flex-col gap-6");
    insertNode(_el$61, _el$62);
    setProp(_el$61, "class", "flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96");
    insertNode(_el$62, _el$63);
    insertNode(_el$62, _el$65);
    setProp(_el$62, "class", "flex flex-col gap-1");
    insertNode(_el$63, createTextNode(`Scroll Region`));
    setProp(_el$63, "class", "text-sm text-foreground");
    setProp(_el$65, "class", "text-xs text-muted-foreground");
    insert(_el$65, scrollDetail);
    insert(_el$61, createComponent2(List, {
      class: "h-40 w-full rounded-md border border-border",
      items: scrollItems,
      itemSize: listItemHeight,
      viewportHeight: listViewportHeight,
      virtual: true,
      itemClass: "flex h-8 items-center rounded-md border border-border px-2 text-sm text-foreground",
      onScroll: logScroll
    }), null);
    insertNode(_el$66, _el$67);
    insertNode(_el$66, _el$69);
    setProp(_el$66, "class", "flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96");
    insertNode(_el$67, createTextNode(`Overlay Staging`));
    setProp(_el$67, "class", "text-sm text-foreground");
    insertNode(_el$69, createTextNode(`Open the modal to validate portal layering and focus trapping.`));
    setProp(_el$69, "class", "text-xs text-muted-foreground");
    insert(_el$66, createComponent2(Button, {
      size: "sm",
      onClick: () => setOverlayOpen(true),
      children: "Open overlay"
    }), null);
    insertNode(_el$71, _el$72);
    insertNode(_el$71, _el$74);
    insertNode(_el$71, _el$75);
    insertNode(_el$71, _el$76);
    insertNode(_el$71, _el$79);
    setProp(_el$71, "class", "flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-96");
    insertNode(_el$72, createTextNode(`Status + Feedback`));
    setProp(_el$72, "class", "text-sm text-foreground");
    setProp(_el$74, "class", "flex flex-row gap-2");
    insert(_el$74, createComponent2(Badge, {
      children: "Beta"
    }), null);
    insert(_el$74, createComponent2(Badge, {
      variant: "secondary",
      children: "Stable"
    }), null);
    insert(_el$74, createComponent2(Badge, {
      variant: "outline",
      children: "Outline"
    }), null);
    setProp(_el$75, "class", "flex flex-row gap-2");
    insert(_el$75, createComponent2(Tag, {
      children: "Internal"
    }), null);
    insert(_el$75, createComponent2(Tag, {
      class: "bg-secondary text-secondary-foreground",
      children: "Release"
    }), null);
    insertNode(_el$76, _el$77);
    setProp(_el$76, "class", "flex flex-row items-center gap-1");
    insertNode(_el$77, createTextNode(`Shortcut`));
    setProp(_el$77, "class", "text-xs text-muted-foreground");
    insert(_el$76, createComponent2(Kbd, {
      children: "\u2318"
    }), null);
    insert(_el$76, createComponent2(Kbd, {
      children: "K"
    }), null);
    insert(_el$71, createComponent2(Alert, {
      title: "Snapshot note",
      children: "Validate new styling before shipping."
    }), _el$79);
    insert(_el$71, createComponent2(DescriptionList, {
      items: [{
        term: "Status",
        description: "Operational"
      }, {
        term: "Region",
        description: "us-east-1"
      }]
    }), _el$79);
    insert(_el$71, createComponent2(Separator, {}), _el$79);
    insert(_el$71, createComponent2(Progress, {
      value: 42
    }), _el$79);
    setProp(_el$79, "class", "flex flex-row gap-2");
    insert(_el$79, createComponent2(Skeleton, {
      class: "h-4 w-24"
    }), null);
    insert(_el$79, createComponent2(Skeleton, {
      class: "h-4 w-16"
    }), null);
    insert(_el$79, createComponent2(Skeleton, {
      class: "h-4 w-12"
    }), null);
    insert(_el$71, createComponent2(Stepper, {
      steps: stepItems,
      get value() {
        return activeStep();
      },
      onChange: setActiveStep
    }), null);
    insert(_el$71, createComponent2(Pagination, {
      get page() {
        return activePage();
      },
      totalPages: 8,
      onChange: setActivePage
    }), null);
    insert(_el$, createComponent2(Show, {
      get when() {
        return overlayOpen();
      },
      get children() {
        var _el$80 = createElement("portal"), _el$81 = createElement("div"), _el$82 = createElement("div"), _el$83 = createElement("h3"), _el$85 = createElement("p"), _el$87 = createElement("div");
        insertNode(_el$80, _el$81);
        setProp(_el$80, "modal", true);
        setProp(_el$80, "focusTrap", true);
        insertNode(_el$81, _el$82);
        setProp(_el$81, "class", "flex h-full w-full items-center justify-center");
        insertNode(_el$82, _el$83);
        insertNode(_el$82, _el$85);
        insertNode(_el$82, _el$87);
        setProp(_el$82, "class", "flex flex-col gap-3 rounded-lg border border-border bg-neutral-900 p-4 w-80");
        insertNode(_el$83, createTextNode(`Overlay Preview`));
        setProp(_el$83, "class", "text-sm text-foreground");
        insertNode(_el$85, createTextNode(`Press buttons and use Tab to ensure focus stays inside.`));
        setProp(_el$85, "class", "text-xs text-muted-foreground");
        setProp(_el$87, "class", "flex flex-row gap-2");
        insert(_el$87, createComponent2(Button, {
          size: "sm",
          onClick: () => setOverlayOpen(false),
          children: "Close"
        }), null);
        insert(_el$87, createComponent2(Button, {
          size: "sm",
          variant: "secondary",
          children: "Action"
        }), null);
        return _el$80;
      }
    }), null);
    effect((_p$) => {
      var _v$ = logEvent("focus"), _v$2 = logEvent("blur"), _v$3 = logEvent("keydown"), _v$4 = logEvent("keyup"), _v$5 = logDrag("dragstart"), _v$6 = logDrag("drag"), _v$7 = logDrag("dragend"), _v$8 = logDrag("dragenter"), _v$9 = logDrag("dragleave"), _v$0 = logDrag("drop");
      _v$ !== _p$.e && (_p$.e = setProp(_el$16, "onFocus", _v$, _p$.e));
      _v$2 !== _p$.t && (_p$.t = setProp(_el$16, "onBlur", _v$2, _p$.t));
      _v$3 !== _p$.a && (_p$.a = setProp(_el$16, "onKeyDown", _v$3, _p$.a));
      _v$4 !== _p$.o && (_p$.o = setProp(_el$16, "onKeyUp", _v$4, _p$.o));
      _v$5 !== _p$.i && (_p$.i = setProp(_el$25, "onDragStart", _v$5, _p$.i));
      _v$6 !== _p$.n && (_p$.n = setProp(_el$25, "onDrag", _v$6, _p$.n));
      _v$7 !== _p$.s && (_p$.s = setProp(_el$25, "onDragEnd", _v$7, _p$.s));
      _v$8 !== _p$.h && (_p$.h = setProp(_el$30, "onDragEnter", _v$8, _p$.h));
      _v$9 !== _p$.r && (_p$.r = setProp(_el$30, "onDragLeave", _v$9, _p$.r));
      _v$0 !== _p$.d && (_p$.d = setProp(_el$30, "onDrop", _v$0, _p$.d));
      return _p$;
    }, {
      e: undefined,
      t: undefined,
      a: undefined,
      o: undefined,
      i: undefined,
      n: undefined,
      s: undefined,
      h: undefined,
      r: undefined,
      d: undefined
    });
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

// solid/state/time.ts
var [elapsedSeconds, setElapsedSeconds] = createSignal(0);
var [deltaSeconds, setDeltaSeconds] = createSignal(0);
var setTime = (elapsed, dt) => {
  setElapsedSeconds(elapsed);
  setDeltaSeconds(dt);
};

// index.ts
var screenWidth = 800;
var screenHeight = 450;
var parseWindowResize = (payload) => {
  if (payload.byteLength < 16)
    return null;
  const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  const width = view.getUint32(0, true);
  const height = view.getUint32(4, true);
  const pixelWidth = view.getUint32(8, true);
  const pixelHeight = view.getUint32(12, true);
  return { width, height, pixelWidth, pixelHeight };
};
var logicalSize = { width: screenWidth, height: screenHeight };
var pixelSize = { width: 0, height: 0 };
var deviceScale = 1;
var pendingResize = null;
var resizeRequested = null;
var computeDeviceScale = (payload) => {
  if (payload.width <= 0 || payload.height <= 0)
    return deviceScale;
  const scaleX = payload.pixelWidth / payload.width;
  const scaleY = payload.pixelHeight / payload.height;
  const scale = Math.max(scaleX, scaleY);
  return Number.isFinite(scale) && scale > 0 ? scale : deviceScale;
};
var requestResize = (width, height) => {
  resizeRequested = { width, height };
  logicalSize = { width, height };
  renderer.resize(width, height);
};
var renderer = new NativeRenderer({
  callbacks: {
    onLog(level, message) {
      console.log(`[native:${level}] ${message}`);
    },
    onEvent(name, payload) {
      if (name === "window_closed") {
        renderer.markNativeClosed();
        requestShutdown(false);
        return;
      }
      if (name === "window_resize") {
        const parsed = parseWindowResize(payload);
        if (!parsed)
          return;
        pendingResize = parsed;
      }
    }
  }
});
requestResize(screenWidth, screenHeight);
var { host: host2, setMessage, dispose } = createSolidTextApp(renderer);
var scheduler = createFrameScheduler();
var running = true;
var frame = 0;
var startTime = performance.now();
var lastTime = startTime;
var pendingShutdown = null;
var requestShutdown = (closeRenderer) => {
  if (!running || pendingShutdown)
    return;
  pendingShutdown = { closeRenderer };
};
var shutdown = ({ closeRenderer = true } = {}) => {
  if (!running)
    return;
  running = false;
  scheduler.stop();
  dispose();
  if (closeRenderer) {
    renderer.close();
  }
};
var drainPendingShutdown = () => {
  if (!pendingShutdown)
    return false;
  const { closeRenderer } = pendingShutdown;
  pendingShutdown = null;
  shutdown({ closeRenderer });
  return true;
};
process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);
process.once("exit", shutdown);
if (undefined) {}
var loop = () => {
  if (!running)
    return false;
  if (drainPendingShutdown())
    return false;
  const now = performance.now();
  const dt = (now - lastTime) / 1000;
  const elapsed = (now - startTime) / 1000;
  lastTime = now;
  setTime(elapsed, dt);
  setMessage(`dvui text @ ${elapsed.toFixed(2)}s (frame ${frame})`);
  host2.flush();
  renderer.present();
  if (drainPendingShutdown())
    return false;
  if (pendingResize) {
    const next = pendingResize;
    pendingResize = null;
    if (resizeRequested && resizeRequested.width === next.width && resizeRequested.height === next.height) {
      resizeRequested = null;
    }
    const logicalChanged = next.width !== logicalSize.width || next.height !== logicalSize.height;
    const pixelChanged = next.pixelWidth !== pixelSize.width || next.pixelHeight !== pixelSize.height;
    if (logicalChanged || pixelChanged) {
      logicalSize = { width: next.width, height: next.height };
      pixelSize = { width: next.pixelWidth, height: next.pixelHeight };
      deviceScale = computeDeviceScale(next);
    }
  }
  const nodeIndex = host2.getNodeIndex?.() ?? new Map;
  renderer.pollEvents(nodeIndex);
  frame += 1;
  return true;
};
scheduler.start(loop);
