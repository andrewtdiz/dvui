// @ts-nocheck
import { createContext, createSignal, Show, splitProps, useContext, JSX } from "solid-js";

export type AccordionType = "single" | "multiple";

export type AccordionProps = {
    type?: AccordionType;
    value?: string | string[];
    defaultValue?: string | string[];
    onChange?: (value: string | string[] | undefined) => void;
    collapsible?: boolean;
    class?: string;
    className?: string;
    children?: JSX.Element;
};

type AccordionContextValue = {
    type: () => AccordionType;
    isOpen: (value: string) => boolean;
    toggle: (value: string) => void;
};

const AccordionContext = createContext<AccordionContextValue>();

const useAccordionContext = () => {
    const ctx = useContext(AccordionContext);
    if (!ctx) {
        throw new Error("Accordion components must be used within an <Accordion> container");
    }
    return ctx;
};

type AccordionItemContextValue = {
    value: () => string;
    isOpen: () => boolean;
    toggle: () => void;
    disabled: () => boolean;
};

const AccordionItemContext = createContext<AccordionItemContextValue>();

const useAccordionItemContext = () => {
    const ctx = useContext(AccordionItemContext);
    if (!ctx) {
        throw new Error("AccordionItem components must be used within an <AccordionItem>");
    }
    return ctx;
};

export const Accordion = (props: AccordionProps) => {
    const [local, others] = splitProps(props, [
        "type",
        "value",
        "defaultValue",
        "onChange",
        "collapsible",
        "class",
        "className",
        "children",
    ]);

    const [internalValue, setInternalValue] = createSignal<string | string[] | undefined>(local.defaultValue);

    const type = () => local.type ?? "single";
    const isControlled = () => local.value !== undefined;
    const currentValue = () => (isControlled() ? local.value : internalValue());

    const setValue = (next: string | string[] | undefined) => {
        if (!isControlled()) {
            setInternalValue(next);
        }
        local.onChange?.(next);
    };

    const isOpen = (value: string) => {
        const valueState = currentValue();
        if (type() === "multiple") {
            return Array.isArray(valueState) && valueState.includes(value);
        }
        return valueState === value;
    };

    const toggle = (value: string) => {
        if (type() === "multiple") {
            const existing = currentValue();
            const list = Array.isArray(existing) ? existing : [];
            const next = list.includes(value)
                ? list.filter((item) => item !== value)
                : [...list, value];
            setValue(next);
            return;
        }

        if (isOpen(value)) {
            if (local.collapsible) {
                setValue(undefined);
            }
            return;
        }

        setValue(value);
    };

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["flex flex-col gap-2", userClass].filter(Boolean).join(" ");
    };

    return (
        <AccordionContext.Provider value={{ type, isOpen, toggle }}>
            <div class={computedClass()} {...others}>
                {local.children}
            </div>
        </AccordionContext.Provider>
    );
};

export type AccordionItemProps = {
    value: string;
    disabled?: boolean;
    class?: string;
    className?: string;
    children?: JSX.Element;
};

export const AccordionItem = (props: AccordionItemProps) => {
    const ctx = useAccordionContext();
    const [local, others] = splitProps(props, ["value", "disabled", "class", "className", "children"]);

    const isOpen = () => ctx.isOpen(local.value);
    const disabled = () => Boolean(local.disabled);
    const toggle = () => {
        if (disabled()) return;
        ctx.toggle(local.value);
    };

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        const state = isOpen() ? "bg-muted" : "bg-transparent";
        const disabledClass = disabled() ? "opacity-50" : "";
        return ["flex flex-col gap-2 rounded-md border border-border p-3", state, disabledClass, userClass]
            .filter(Boolean)
            .join(" ");
    };

    return (
        <AccordionItemContext.Provider value={{ value: () => local.value, isOpen, toggle, disabled }}>
            <div class={computedClass()} {...others}>
                {local.children}
            </div>
        </AccordionItemContext.Provider>
    );
};

export type AccordionTriggerProps = JSX.ButtonHTMLAttributes<HTMLButtonElement> & {
    class?: string;
    className?: string;
};

export const AccordionTrigger = (props: AccordionTriggerProps) => {
    const item = useAccordionItemContext();
    const [local, others] = splitProps(props, ["class", "className", "children", "disabled", "onClick"]);

    const disabled = () => Boolean(local.disabled ?? item.disabled());

    const handleClick = (event: any) => {
        if (disabled()) return;
        item.toggle();
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
            ariaExpanded={item.isOpen()}
            ariaDisabled={disabled()}
            disabled={disabled()}
            onClick={handleClick}
            {...others}
        >
            {local.children}
        </button>
    );
};

export type AccordionContentProps = JSX.HTMLAttributes<HTMLDivElement> & {
    forceMount?: boolean;
    class?: string;
    className?: string;
};

export const AccordionContent = (props: AccordionContentProps) => {
    const item = useAccordionItemContext();
    const [local, others] = splitProps(props, ["forceMount", "class", "className", "children"]);

    const computedClass = (hidden = false) => {
        const userClass = local.class ?? local.className ?? "";
        const hiddenClass = hidden ? "hidden" : "";
        return ["text-sm text-muted-foreground", hiddenClass, userClass].filter(Boolean).join(" ");
    };

    if (local.forceMount) {
        return (
            <div class={computedClass(!item.isOpen())} ariaHidden={!item.isOpen()} {...others}>
                {local.children}
            </div>
        );
    }

    return (
        <Show when={item.isOpen()}>
            <div class={computedClass(false)} ariaHidden={false} {...others}>
                {local.children}
            </div>
        </Show>
    );
};
