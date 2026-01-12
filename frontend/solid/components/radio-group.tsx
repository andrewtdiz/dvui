// @ts-nocheck
import { createContext, createSignal, Show, splitProps, useContext, JSX } from "solid-js";

export type RadioGroupProps = {
    value?: string;
    defaultValue?: string;
    onChange?: (value: string) => void;
    class?: string;
    className?: string;
    children?: JSX.Element;
};

type RadioGroupContextValue = {
    value: () => string | undefined;
    setValue: (value: string) => void;
    isControlled: () => boolean;
};

const RadioGroupContext = createContext<RadioGroupContextValue>();

const useRadioGroupContext = () => {
    const ctx = useContext(RadioGroupContext);
    if (!ctx) {
        throw new Error("Radio components must be used within a <RadioGroup> container");
    }
    return ctx;
};

export const RadioGroup = (props: RadioGroupProps) => {
    const [local, others] = splitProps(props, [
        "value",
        "defaultValue",
        "onChange",
        "class",
        "className",
        "children",
    ]);

    const [internalValue, setInternalValue] = createSignal<string | undefined>(local.defaultValue);

    const isControlled = () => local.value !== undefined;
    const currentValue = () => (isControlled() ? local.value : internalValue());
    const setValue = (value: string) => {
        if (!isControlled()) {
            setInternalValue(value);
        }
        local.onChange?.(value);
    };

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["flex flex-col gap-2", userClass].filter(Boolean).join(" ");
    };

    return (
        <RadioGroupContext.Provider value={{ value: currentValue, setValue, isControlled }}>
            <div class={computedClass()} role="radiogroup" roving={true} {...others}>
                {local.children}
            </div>
        </RadioGroupContext.Provider>
    );
};

export type RadioProps = JSX.ButtonHTMLAttributes<HTMLButtonElement> & {
    value: string;
    label?: string;
    class?: string;
    className?: string;
};

export const Radio = (props: RadioProps) => {
    const ctx = useRadioGroupContext();
    const [local, others] = splitProps(props, [
        "value",
        "label",
        "class",
        "className",
        "disabled",
        "onClick",
        "onFocus",
    ]);

    const isChecked = () => ctx.value() === local.value;

    const handleActivate = (event: any) => {
        if (local.disabled) return;
        ctx.setValue(local.value);
        return event;
    };

    const handleClick = (event: any) => {
        handleActivate(event);
        local.onClick?.(event);
    };

    const handleFocus = (event: any) => {
        handleActivate(event);
        local.onFocus?.(event);
    };

    const wrapperClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["flex items-center gap-2", userClass].filter(Boolean).join(" ");
    };

    const radioClasses = () => {
        const base = isChecked()
            ? "bg-primary text-primary-foreground border border-primary"
            : "bg-transparent text-foreground border border-input";
        const size = "h-4 w-4 rounded-full";
        const disabled = local.disabled ? "opacity-50" : "";
        return ["flex items-center justify-center text-xs", size, base, disabled].filter(Boolean).join(" ");
    };

    const labelClass = () => {
        const disabled = local.disabled ? "opacity-50" : "";
        return ["text-sm text-foreground", disabled].filter(Boolean).join(" ");
    };

    const dotSymbol = () => isChecked() ? "●" : " ";

    return (
        <div class={wrapperClass()}>
            <button
                class={radioClasses()}
                onClick={handleClick}
                onFocus={handleFocus}
                disabled={local.disabled}
                role="radio"
                ariaChecked={isChecked()}
                ariaDisabled={local.disabled}
                ariaLabel={local.label}
                {...others}
            >
                {dotSymbol()}
            </button>
            <Show when={local.label}>
                <p class={labelClass()}>{local.label}</p>
            </Show>
        </div>
    );
};
