// @ts-nocheck
import { splitProps, JSX } from "solid-js";

export type ScrollableProps = {
    class?: string;
    className?: string;
    scrollX?: number;
    scrollY?: number;
    canvasWidth?: number;
    canvasHeight?: number;
    autoCanvas?: boolean;
    onScroll?: (payload: Uint8Array) => void;
    children?: JSX.Element;
};

export const Scrollable = (props: ScrollableProps) => {
    const [local, others] = splitProps(props, [
        "class",
        "className",
        "scrollX",
        "scrollY",
        "canvasWidth",
        "canvasHeight",
        "autoCanvas",
        "onScroll",
        "children",
    ]);

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["overflow-hidden", userClass].filter(Boolean).join(" ");
    };

    return (
        <div
            class={computedClass()}
            scroll={true}
            scrollX={local.scrollX}
            scrollY={local.scrollY}
            canvasWidth={local.canvasWidth}
            canvasHeight={local.canvasHeight}
            autoCanvas={local.autoCanvas ?? true}
            onScroll={local.onScroll}
            {...others}
        >
            {local.children}
        </div>
    );
};
