// @ts-nocheck
import { createSignal, splitProps } from "solid-js";
import { decodeTextPayload } from "./input-utils";

export type InputProps = {
    value?: string;
    defaultValue?: string;
    placeholder?: string;
    onChange?: (value: string) => void;
    validate?: (value: string) => boolean;
    onInvalid?: (value: string) => void;
    disabled?: boolean;
    class?: string;
    className?: string;
};

export const Input = (props: InputProps) => {
    const [local, others] = splitProps(props, [
        "value",
        "defaultValue",
        "placeholder",
        "onChange",
        "validate",
        "onInvalid",
        "disabled",
        "class",
        "className",
        "onInput",
    ]);

    const [localValue, setLocalValue] = createSignal(local.defaultValue ?? "");
    const isControlled = () => local.value !== undefined;
    const displayValue = () => (isControlled() ? local.value ?? "" : localValue());

    const handleInput = (event: any) => {
        if (local.disabled) return;
        const nextValue = decodeTextPayload(event);
        if (!isControlled()) {
            setLocalValue(nextValue);
        }
        const valid = local.validate ? local.validate(nextValue) : true;
        if (!valid) {
            local.onInvalid?.(nextValue);
        } else {
            local.onChange?.(nextValue);
        }
        local.onInput?.(event);
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
            disabled={local.disabled}
            {...others}
        />
    );
};
