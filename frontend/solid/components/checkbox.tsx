// @ts-nocheck
import { createSignal, Show } from "solid-js";

export type CheckboxProps = {
    checked?: boolean;
    defaultChecked?: boolean;
    onChange?: (checked: boolean) => void;
    disabled?: boolean;
    label?: string;
    class?: string;
    className?: string;
};

export const Checkbox = (props: CheckboxProps) => {
    const [internalChecked, setInternalChecked] = createSignal(props.defaultChecked ?? false);

    const isChecked = () => props.checked !== undefined ? props.checked : internalChecked();

    const handleClick = () => {
        if (props.disabled) return;
        const newValue = !isChecked();
        if (props.checked === undefined) {
            setInternalChecked(newValue);
        }
        props.onChange?.(newValue);
    };

    const wrapperClass = () => {
        const userClass = props.class ?? props.className ?? "";
        return ["flex items-center gap-2", userClass].filter(Boolean).join(" ");
    };

    const boxClasses = () => {
        const base = isChecked()
            ? "bg-primary text-primary-foreground border border-primary"
            : "bg-transparent text-foreground border border-input";
        const size = "h-4 w-4 rounded-sm";
        const disabled = props.disabled ? "opacity-50" : "";
        return ["flex items-center justify-center text-xs", size, base, disabled].filter(Boolean).join(" ");
    };

    const labelClass = () => {
        const disabled = props.disabled ? "opacity-50" : "";
        return ["text-sm text-foreground", disabled].filter(Boolean).join(" ");
    };

    // Use text symbol that's always present to avoid DVUI rendering "button" as text
    const checkSymbol = () => isChecked() ? "✓" : " ";

    return (
        <div class={wrapperClass()}>
            <button
                class={boxClasses()}
                onClick={handleClick}
                disabled={props.disabled}
                role="checkbox"
                ariaChecked={isChecked()}
                ariaDisabled={props.disabled}
                ariaLabel={props.label}
            >
                {checkSymbol()}
            </button>
            <Show when={props.label}>
                <p class={labelClass()}>{props.label}</p>
            </Show>
        </div>
    );
};
