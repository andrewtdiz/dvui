export const DVUI_APP_KEY = "dvuiApp";

export function ensureNativeAppState() {
  if (!globalThis[DVUI_APP_KEY]) {
    globalThis[DVUI_APP_KEY] = { commands: [], rootIds: [], version: 0 };
  }
  return globalThis[DVUI_APP_KEY];
}

export function publishRenderSnapshot(snapshot) {
  if (!snapshot || !Array.isArray(snapshot.commands) || !Array.isArray(snapshot.rootIds)) {
    throw new Error("Invalid snapshot");
  }
  const previousVersion = globalThis[DVUI_APP_KEY]?.version ?? 0;
  globalThis[DVUI_APP_KEY] = {
    commands: snapshot.commands,
    rootIds: snapshot.rootIds,
    version: previousVersion + 1,
  };
}
