// @ts-nocheck
import { createSignal, splitProps } from "solid-js";
import { decodeTextPayload, normalizeKeyPayload } from "./input-utils";

export type NumberInputProps = {
    value?: number;
    defaultValue?: number;
    min?: number;
    max?: number;
    step?: number;
    placeholder?: string;
    onChange?: (value: number) => void;
    validate?: (value: number) => boolean;
    onInvalid?: (raw: string) => void;
    disabled?: boolean;
    class?: string;
    className?: string;
};

export const NumberInput = (props: NumberInputProps) => {
    const [local, others] = splitProps(props, [
        "value",
        "defaultValue",
        "min",
        "max",
        "step",
        "placeholder",
        "onChange",
        "validate",
        "onInvalid",
        "disabled",
        "class",
        "className",
        "onInput",
        "onKeyDown",
    ]);

    const initialValue = () => {
        const seed = local.defaultValue;
        return typeof seed === "number" && Number.isFinite(seed) ? String(seed) : "";
    };

    const [rawValue, setRawValue] = createSignal(initialValue());
    const isControlled = () => local.value !== undefined;

    const displayValue = () => {
        if (isControlled()) {
            const value = Number(local.value);
            return Number.isFinite(value) ? String(value) : "";
        }
        return rawValue();
    };

    const parseNumber = (raw: string) => {
        const trimmed = raw.trim();
        if (trimmed.length === 0) return null;
        const value = Number(trimmed);
        if (!Number.isFinite(value)) return null;
        return value;
    };

    const clampNumber = (value: number) => {
        let next = value;
        const min = Number(local.min);
        const max = Number(local.max);
        if (Number.isFinite(min)) {
            next = Math.max(min, next);
        }
        if (Number.isFinite(max)) {
            next = Math.min(max, next);
        }
        return next;
    };

    const stepSize = (scale = 1) => {
        const step = Number(local.step ?? 1);
        const base = Number.isFinite(step) && step !== 0 ? step : 1;
        return base * scale;
    };

    const emitValue = (value: number, raw?: string) => {
        const clamped = clampNumber(value);
        const valid = local.validate ? local.validate(clamped) : true;
        if (!valid) {
            local.onInvalid?.(raw ?? String(clamped));
            return;
        }
        if (!isControlled()) {
            setRawValue(raw ?? String(clamped));
        }
        local.onChange?.(clamped);
    };

    const handleInput = (event: any) => {
        if (local.disabled) return;
        const nextRaw = decodeTextPayload(event);
        if (!isControlled()) {
            setRawValue(nextRaw);
        }
        const parsed = parseNumber(nextRaw);
        if (parsed == null) {
            local.onInvalid?.(nextRaw);
            local.onInput?.(event);
            return;
        }
        emitValue(parsed, nextRaw);
        local.onInput?.(event);
    };

    const handleKeyDown = (event: any) => {
        if (local.disabled) {
            local.onKeyDown?.(event);
            return;
        }
        const key = normalizeKeyPayload(event);
        const current = parseNumber(displayValue());
        const base = current ?? (Number.isFinite(Number(local.min)) ? Number(local.min) : 0);
        let handled = false;

        switch (key) {
            case "up":
            case "page_up": {
                const scale = key === "page_up" ? 10 : 1;
                emitValue(base + stepSize(scale));
                handled = true;
                break;
            }
            case "down":
            case "page_down": {
                const scale = key === "page_down" ? 10 : 1;
                emitValue(base - stepSize(scale));
                handled = true;
                break;
            }
            case "home": {
                const min = Number(local.min);
                if (Number.isFinite(min)) {
                    emitValue(min);
                    handled = true;
                }
                break;
            }
            case "end": {
                const max = Number(local.max);
                if (Number.isFinite(max)) {
                    emitValue(max);
                    handled = true;
                }
                break;
            }
            default:
                break;
        }

        if (handled && typeof event?.preventDefault === "function") {
            event.preventDefault();
        }
        local.onKeyDown?.(event);
    };

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        const disabled = local.disabled ? "opacity-50" : "";
        return `h-10 rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground ${disabled} ${userClass}`;
    };

    return (
        <input
            class={computedClass()}
            value={displayValue()}
            placeholder={local.placeholder}
            onInput={handleInput}
            onKeyDown={handleKeyDown}
            disabled={local.disabled}
            {...others}
        />
    );
};
