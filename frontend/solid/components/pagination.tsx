// @ts-nocheck
import { createMemo, createSignal, splitProps } from "solid-js";

export type PaginationProps = {
    page?: number;
    defaultPage?: number;
    totalPages: number;
    siblingCount?: number;
    onChange?: (page: number) => void;
    class?: string;
    className?: string;
};

const clampPaginationPage = (value: number, totalPages: number) => {
    if (!Number.isFinite(totalPages) || totalPages <= 0) return 1;
    const normalized = Number.isFinite(value) ? Math.floor(value) : 1;
    return Math.min(Math.floor(totalPages), Math.max(1, normalized));
};

const buildPaginationRange = (current: number, total: number, siblingCount: number) => {
    const totalPages = Math.max(1, Math.floor(total));
    const clampedCurrent = clampPaginationPage(current, totalPages);
    const count = Math.max(0, Math.floor(siblingCount));

    const totalPageNumbers = count * 2 + 5;
    if (totalPages <= totalPageNumbers) {
        return Array.from({ length: totalPages }, (_, index) => index + 1);
    }

    const leftSiblingIndex = Math.max(clampedCurrent - count, 1);
    const rightSiblingIndex = Math.min(clampedCurrent + count, totalPages);

    const showLeftEllipsis = leftSiblingIndex > 2;
    const showRightEllipsis = rightSiblingIndex < totalPages - 1;

    if (!showLeftEllipsis && showRightEllipsis) {
        const leftItemCount = 3 + count * 2;
        return [
            ...Array.from({ length: leftItemCount }, (_, index) => index + 1),
            "ellipsis",
            totalPages,
        ];
    }

    if (showLeftEllipsis && !showRightEllipsis) {
        const rightItemCount = 3 + count * 2;
        const start = totalPages - rightItemCount + 1;
        return [
            1,
            "ellipsis",
            ...Array.from({ length: rightItemCount }, (_, index) => start + index),
        ];
    }

    return [
        1,
        "ellipsis",
        ...Array.from({ length: rightSiblingIndex - leftSiblingIndex + 1 }, (_, index) => leftSiblingIndex + index),
        "ellipsis",
        totalPages,
    ];
};

export const Pagination = (props: PaginationProps) => {
    const [local, others] = splitProps(props, [
        "page",
        "defaultPage",
        "totalPages",
        "siblingCount",
        "onChange",
        "class",
        "className",
    ]);

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

    const setPage = (nextPage: number) => {
        const next = clampPaginationPage(nextPage, totalPages());
        if (next === currentPage()) return;
        if (local.page === undefined) {
            setInternalPage(next);
        }
        local.onChange?.(next);
    };

    const buttonClass = (active: boolean, disabled: boolean) => {
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

    return (
        <div class={computedClass()} {...others}>
            <button
                class={buttonClass(false, !canPrev())}
                onClick={() => setPage(currentPage() - 1)}
                disabled={!canPrev()}
                ariaDisabled={!canPrev()}
                ariaLabel="Previous page"
            >
                <p class="text-xs">‹</p>
            </button>
            {pageItems().map((item) => {
                if (item === "ellipsis") {
                    return <p class="px-2 text-xs text-muted-foreground">…</p>;
                }

                const isActive = item === currentPage();
                return (
                    <button
                        class={buttonClass(isActive, false)}
                        onClick={() => setPage(item)}
                        ariaSelected={isActive}
                        ariaLabel={`Page ${item}`}
                    >
                        <p class="text-xs">{item}</p>
                    </button>
                );
            })}
            <button
                class={buttonClass(false, !canNext())}
                onClick={() => setPage(currentPage() + 1)}
                disabled={!canNext()}
                ariaDisabled={!canNext()}
                ariaLabel="Next page"
            >
                <p class="text-xs">›</p>
            </button>
        </div>
    );
};
