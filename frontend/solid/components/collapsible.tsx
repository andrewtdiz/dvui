// @ts-nocheck
import { createContext, createSignal, Show, splitProps, useContext, JSX } from "solid-js";

export type CollapsibleProps = {
    open?: boolean;
    defaultOpen?: boolean;
    onChange?: (open: boolean) => void;
    disabled?: boolean;
    class?: string;
    className?: string;
    children?: JSX.Element;
};

type CollapsibleContextValue = {
    open: () => boolean;
    setOpen: (open: boolean) => void;
    toggle: () => void;
    disabled: () => boolean;
};

const CollapsibleContext = createContext<CollapsibleContextValue>();

const useCollapsibleContext = () => {
    const ctx = useContext(CollapsibleContext);
    if (!ctx) {
        throw new Error("Collapsible components must be used within a <Collapsible> container");
    }
    return ctx;
};

export const Collapsible = (props: CollapsibleProps) => {
    const [local, others] = splitProps(props, [
        "open",
        "defaultOpen",
        "onChange",
        "disabled",
        "class",
        "className",
        "children",
    ]);

    const [internalOpen, setInternalOpen] = createSignal(local.defaultOpen ?? false);

    const isControlled = () => local.open !== undefined;
    const isOpen = () => (isControlled() ? Boolean(local.open) : internalOpen());

    const setOpen = (next: boolean) => {
        if (!isControlled()) {
            setInternalOpen(next);
        }
        local.onChange?.(next);
    };

    const toggle = () => {
        if (local.disabled) return;
        setOpen(!isOpen());
    };

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["flex flex-col gap-2", userClass].filter(Boolean).join(" ");
    };

    return (
        <CollapsibleContext.Provider value={{ open: isOpen, setOpen, toggle, disabled: () => Boolean(local.disabled) }}>
            <div class={computedClass()} {...others}>
                {local.children}
            </div>
        </CollapsibleContext.Provider>
    );
};

export type CollapsibleTriggerProps = JSX.ButtonHTMLAttributes<HTMLButtonElement> & {
    class?: string;
    className?: string;
};

export const CollapsibleTrigger = (props: CollapsibleTriggerProps) => {
    const ctx = useCollapsibleContext();
    const [local, others] = splitProps(props, ["class", "className", "children", "disabled", "onClick"]);

    const disabled = () => Boolean(local.disabled ?? ctx.disabled());

    const handleClick = (event: any) => {
        if (disabled()) return;
        ctx.toggle();
        local.onClick?.(event);
    };

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        const base = "flex w-full items-center justify-between text-sm text-foreground";
        const disabledClass = disabled() ? "opacity-50" : "";
        return [base, disabledClass, userClass].filter(Boolean).join(" ");
    };

    return (
        <button
            class={computedClass()}
            ariaExpanded={ctx.open()}
            ariaDisabled={disabled()}
            disabled={disabled()}
            onClick={handleClick}
            {...others}
        >
            {local.children}
        </button>
    );
};

export type CollapsibleContentProps = JSX.HTMLAttributes<HTMLDivElement> & {
    forceMount?: boolean;
    class?: string;
    className?: string;
};

export const CollapsibleContent = (props: CollapsibleContentProps) => {
    const ctx = useCollapsibleContext();
    const [local, others] = splitProps(props, ["forceMount", "class", "className", "children"]);

    const computedClass = (hidden = false) => {
        const userClass = local.class ?? local.className ?? "";
        const hiddenClass = hidden ? "hidden" : "";
        return ["text-sm text-muted-foreground", hiddenClass, userClass].filter(Boolean).join(" ");
    };

    if (local.forceMount) {
        return (
            <div class={computedClass(!ctx.open())} ariaHidden={!ctx.open()} {...others}>
                {local.children}
            </div>
        );
    }

    return (
        <Show when={ctx.open()}>
            <div class={computedClass(false)} ariaHidden={false} {...others}>
                {local.children}
            </div>
        </Show>
    );
};
