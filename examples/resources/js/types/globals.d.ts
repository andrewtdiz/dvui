export {};

declare global {
    interface FrameArgs {
        position: number;
        dt: number;
    }

    interface MouseState {
        x: number;
        y: number;
    }

    interface QuickJsStd {
        printf(format: string, ...args: unknown[]): void;
    }

    type WindowEventType =
        | "mousedown"
        | "mouseup"
        | "click"
        | "keydown"
        | "keyup"
        | "keypress";

    type MouseButton = "left" | "right";

    interface MouseWindowEvent {
        type: "mousedown" | "mouseup" | "click";
        button: MouseButton;
        x: number;
        y: number;
    }

    interface KeyWindowEvent {
        type: "keydown" | "keyup" | "keypress";
        code: "KeyG" | "KeyR" | "KeyS";
        repeat: boolean;
    }

    type WindowEventDetail = MouseWindowEvent | KeyWindowEvent;

    interface WindowLike {
        addEventListener(type: WindowEventType, listener: (event: WindowEventDetail) => void): void;
        removeEventListener(type: WindowEventType, listener: (event: WindowEventDetail) => void): void;
    }

    interface EditorTickApi {
        Connect(callback: (frame: FrameArgs) => number): void;
    }

    interface EditorHandles {
        Tick: EditorTickApi;
    }

    var mouse: MouseState;
    var std: QuickJsStd;
    var window: WindowLike;
    var editor: EditorHandles;
    var __clayRuntimeBootstrapped: boolean | undefined;
    function __dispatchWindowEvent(type: WindowEventType, detail: WindowEventDetail): void;
    function runFrame(frame: FrameArgs): number;
}
