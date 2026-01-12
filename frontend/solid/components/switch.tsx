// @ts-nocheck
import { createSignal, splitProps } from "solid-js";

export type SwitchProps = {
    checked?: boolean;
    defaultChecked?: boolean;
    onChange?: (checked: boolean) => void;
    disabled?: boolean;
    class?: string;
    className?: string;
    role?: string;
    ariaLabel?: string;
};

export const Switch = (props: SwitchProps) => {
    const [local, others] = splitProps(props, [
        "checked",
        "defaultChecked",
        "onChange",
        "disabled",
        "class",
        "className",
        "role",
        "ariaLabel",
        "onClick",
    ]);

    const [internalChecked, setInternalChecked] = createSignal(local.defaultChecked ?? false);

    const isChecked = () => local.checked !== undefined ? local.checked : internalChecked();

    const handleClick = (event: any) => {
        if (local.disabled) return;
        const newValue = !isChecked();
        if (local.checked === undefined) {
            setInternalChecked(newValue);
        }
        local.onChange?.(newValue);
        local.onClick?.(event);
    };

    const trackClass = () => {
        const userClass = local.class ?? local.className ?? "";
        const base = isChecked() ? "bg-primary" : "bg-input";
        const disabled = local.disabled ? "opacity-50" : "";
        return ["flex flex-row items-center h-6 w-11 rounded-full", base, disabled, userClass]
            .filter(Boolean)
            .join(" ");
    };

    // Thumb: white circle, positioned left when off, right when on
    const thumbClass = () => {
        return "h-5 w-5 rounded-full bg-white";
    };

    // Spacer to push thumb to the right when checked
    const spacerClass = () => {
        return isChecked() ? "w-5" : "w-px";
    };

    return (
        <button
            class={trackClass()}
            onClick={handleClick}
            disabled={local.disabled}
            role={local.role ?? "switch"}
            ariaChecked={isChecked()}
            ariaDisabled={local.disabled}
            ariaLabel={local.ariaLabel}
            {...others}
        >
            <div class={spacerClass()}> </div>
            <div class={thumbClass()}> </div>
        </button>
    );
};
