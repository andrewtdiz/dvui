// @ts-nocheck
import { createSignal, splitProps, JSX } from "solid-js";

export type ToggleProps = {
    pressed?: boolean;
    defaultPressed?: boolean;
    onChange?: (pressed: boolean) => void;
    disabled?: boolean;
    class?: string;
    className?: string;
    role?: string;
    ariaLabel?: string;
    children?: JSX.Element;
};

export const Toggle = (props: ToggleProps) => {
    const [local, others] = splitProps(props, [
        "pressed",
        "defaultPressed",
        "onChange",
        "disabled",
        "class",
        "className",
        "role",
        "ariaLabel",
        "children",
        "onClick",
    ]);

    const [internalPressed, setInternalPressed] = createSignal(local.defaultPressed ?? false);

    const isPressed = () => local.pressed !== undefined ? local.pressed : internalPressed();

    const handleClick = (event: any) => {
        if (local.disabled) return;
        const nextValue = !isPressed();
        if (local.pressed === undefined) {
            setInternalPressed(nextValue);
        }
        local.onChange?.(nextValue);
        local.onClick?.(event);
    };

    const toggleClass = () => {
        const userClass = local.class ?? local.className ?? "";
        const base = "inline-flex items-center justify-center rounded-md border px-3 py-1 text-sm";
        const state = isPressed()
            ? "bg-primary text-primary-foreground border-primary"
            : "bg-transparent text-foreground border-input";
        const disabled = local.disabled ? "opacity-50" : "";
        return [base, state, disabled, userClass].filter(Boolean).join(" ");
    };

    return (
        <button
            class={toggleClass()}
            onClick={handleClick}
            disabled={local.disabled}
            role={local.role ?? "button"}
            ariaPressed={isPressed()}
            ariaDisabled={local.disabled}
            ariaLabel={local.ariaLabel}
            {...others}
        >
            {local.children}
        </button>
    );
};
