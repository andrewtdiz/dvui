// @ts-nocheck
import { createSignal, mergeProps } from "solid-js";

export type SliderProps = {
    value?: number;
    defaultValue?: number;
    min?: number;
    max?: number;
    step?: number;
    onChange?: (value: number) => void;
    disabled?: boolean;
    class?: string;
    className?: string;
};

export const Slider = (props: SliderProps) => {
    const merged = mergeProps({ min: 0, max: 100 }, props);
    const [internalValue, setInternalValue] = createSignal(props.defaultValue ?? merged.min);

    const clampValue = (val: number) => {
        const min = Number(merged.min);
        const max = Number(merged.max);
        if (!Number.isFinite(val)) return min;
        if (!Number.isFinite(max) || max <= min) return min;
        return Math.min(max, Math.max(min, val));
    };

    const toFraction = (val: number) => {
        const min = Number(merged.min);
        const max = Number(merged.max);
        const range = max - min;
        if (!Number.isFinite(range) || range <= 0) return 0;
        return Math.min(1, Math.max(0, (val - min) / range));
    };

    const fromFraction = (fraction: number) => {
        const min = Number(merged.min);
        const max = Number(merged.max);
        const range = max - min;
        if (!Number.isFinite(range) || range <= 0) return min;
        return min + fraction * range;
    };

    const applyStep = (val: number) => {
        const step = Number(merged.step);
        if (!Number.isFinite(step) || step <= 0) return val;
        const min = Number(merged.min);
        const snapped = Math.round((val - min) / step) * step + min;
        return clampValue(snapped);
    };

    const currentValue = () => {
        const value = props.value !== undefined ? props.value : internalValue();
        return clampValue(value);
    };

    const handleInput = (e: any) => {
        if (props.disabled) return;
        let raw: number;
        if (e?.target?.value !== undefined) {
            raw = Number(e.target.value);
        } else if (e?.detail !== undefined) {
            raw = Number(e.detail);
        } else if (e instanceof Uint8Array) {
            raw = Number(new TextDecoder().decode(e));
        } else {
            raw = Number(e ?? 0);
        }

        const fraction = Math.min(1, Math.max(0, Number.isFinite(raw) ? raw : 0));
        const nextValue = applyStep(fromFraction(fraction));
        if (props.value === undefined) {
            setInternalValue(nextValue);
        }
        props.onChange?.(nextValue);
    };

    const computedClass = () => {
        const userClass = props.class ?? props.className ?? "";
        const disabled = props.disabled ? "opacity-50" : "";
        return `w-full h-4 rounded-full ${disabled} ${userClass}`;
    };

    return (
        <slider
            class={computedClass()}
            value={toFraction(currentValue())}
            onInput={handleInput}
            ariaDisabled={props.disabled}
        />
    );
};
