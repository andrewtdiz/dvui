// @ts-nocheck
import { createSignal } from "solid-js";

export type TextareaProps = {
    value?: string;
    placeholder?: string;
    onChange?: (value: string) => void;
    disabled?: boolean;
    rows?: number;
    class?: string;
};

export const Textarea = (props: TextareaProps) => {
    const [localValue, setLocalValue] = createSignal(props.value ?? "");

    const displayValue = () => props.value !== undefined ? props.value : localValue();

    const handleInput = (e: any) => {
        let newValue: string;
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

    return (
        <textarea
            class={computedClass()}
            value={displayValue()}
            placeholder={props.placeholder}
            rows={props.rows ?? 3}
            onInput={handleInput}
            disabled={props.disabled}
        />
    );
};
