// @ts-nocheck
import { createMemo, createSignal, JSX } from "solid-js";
import { computeVirtualRange, parseScrollDetail } from "../runtime";
import { Scrollable } from "./scrollable";

export type ListProps<T> = {
    items: T[];
    renderItem?: (item: T, index: number) => JSX.Element;
    class?: string;
    className?: string;
    contentClass?: string;
    contentClassName?: string;
    itemClass?: string;
    itemClassName?: string;
    virtual?: boolean;
    itemSize?: number;
    overscan?: number;
    viewportHeight?: number;
    scrollX?: number;
    scrollY?: number;
    canvasWidth?: number;
    canvasHeight?: number;
    autoCanvas?: boolean;
    onScroll?: (payload: Uint8Array) => void;
};

const decodeScrollPayload = (payload?: Uint8Array) => {
    if (!payload || payload.length === 0) return "";
    return new TextDecoder().decode(payload);
};

export const List = <T,>(props: ListProps<T>) => {
    const [scrollDetail, setScrollDetail] = createSignal<ReturnType<typeof parseScrollDetail>>(null);

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
            return { start: 0, end: total, offset: 0 };
        }

        const detail = scrollDetail();
        const viewportSize = detail?.viewportHeight ?? props.viewportHeight ?? 0;
        if (!Number.isFinite(viewportSize) || viewportSize <= 0) {
            return { start: 0, end: total, offset: 0 };
        }

        return computeVirtualRange({
            itemCount: total,
            itemSize: itemSize(),
            viewportSize,
            scrollOffset: detail?.offsetY ?? 0,
            overscan: props.overscan,
        });
    });

    const visibleItems = createMemo(() => {
        const all = items();
        if (!isVirtual()) return all;
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
        return undefined;
    });

    const contentClass = () => {
        const userClass = props.contentClass ?? props.contentClassName ?? "";
        return ["flex flex-col", userClass].filter(Boolean).join(" ");
    };

    const itemClass = () => props.itemClass ?? props.itemClassName ?? "";

    const offsetStyle = () => {
        if (!isVirtual()) return undefined;
        return { transform: `translateY(${virtualRange().offset}px)` };
    };

    const itemStyle = () => {
        if (!isVirtual()) return undefined;
        const size = itemSize();
        if (!size) return undefined;
        return { height: `${size}px` };
    };

    const handleScroll = (payload: Uint8Array) => {
        const detail = parseScrollDetail(decodeScrollPayload(payload));
        if (detail) {
            setScrollDetail(detail);
        }
        if (typeof props.onScroll === "function") {
            props.onScroll(payload);
        }
    };

    const renderItem = (item: T, index: number) => {
        if (typeof props.renderItem === "function") {
            return props.renderItem(item, index);
        }
        return item as JSX.Element;
    };

    const renderedItems = () => {
        const range = virtualRange();
        return visibleItems().map((item, index) => {
            const realIndex = isVirtual() ? range.start + index : index;
            return (
                <div class={itemClass()} style={itemStyle()}>
                    {renderItem(item, realIndex)}
                </div>
            );
        });
    };

    const listClass = () => props.class ?? props.className ?? "";
    const autoCanvas = () => props.autoCanvas ?? !isVirtual();

    return (
        <Scrollable
            class={listClass()}
            scrollX={props.scrollX}
            scrollY={props.scrollY}
            canvasWidth={props.canvasWidth}
            canvasHeight={totalHeight()}
            autoCanvas={autoCanvas()}
            onScroll={handleScroll}
        >
            <div class={contentClass()} style={offsetStyle()}>
                {renderedItems()}
            </div>
        </Scrollable>
    );
};
