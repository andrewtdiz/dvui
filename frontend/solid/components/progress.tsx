// @ts-nocheck
import { mergeProps } from "solid-js";

export type ProgressProps = {
    value?: number;  // 0-100
    max?: number;
    class?: string;
    className?: string;
};

export const Progress = (props: ProgressProps) => {
    const merged = mergeProps({ value: 0, max: 100 }, props);

    const percentage = () => {
        const max = Number(merged.max);
        const value = Number(merged.value);
        if (!Number.isFinite(max) || max <= 0) return 0;
        if (!Number.isFinite(value)) return 0;
        return Math.min(100, Math.max(0, (value / max) * 100));
    };

    const userClass = props.class ?? props.className ?? "";

    return (
        <div class={`h-2 w-full overflow-hidden rounded-full bg-secondary ${userClass}`}>
            <div
                class="h-full bg-primary"
                style={{ width: `${percentage()}%` }}
            />
        </div>
    );
};
