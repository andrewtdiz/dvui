// @ts-nocheck
import { createContext, createEffect, createSignal, Show, splitProps, useContext, JSX } from "solid-js";

export type TabsOrientation = "horizontal" | "vertical";

export type TabsProps = {
    value?: string;
    defaultValue?: string;
    onChange?: (value: string) => void;
    orientation?: TabsOrientation;
    class?: string;
    className?: string;
    children?: JSX.Element;
};

type TabsContextValue = {
    value: () => string | undefined;
    setValue: (value: string) => void;
    orientation: () => TabsOrientation;
    isControlled: () => boolean;
};

const TabsContext = createContext<TabsContextValue>();

const useTabsContext = () => {
    const ctx = useContext(TabsContext);
    if (!ctx) {
        throw new Error("Tabs components must be used within a <Tabs> container");
    }
    return ctx;
};

export const Tabs = (props: TabsProps) => {
    const [local, others] = splitProps(props, [
        "value",
        "defaultValue",
        "onChange",
        "orientation",
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
    const orientation = () => local.orientation ?? "horizontal";

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["flex flex-col gap-2", userClass].filter(Boolean).join(" ");
    };

    return (
        <TabsContext.Provider value={{ value: currentValue, setValue, orientation, isControlled }}>
            <div class={computedClass()} {...others}>
                {local.children}
            </div>
        </TabsContext.Provider>
    );
};

export type TabsListProps = {
    class?: string;
    className?: string;
    children?: JSX.Element;
};

export const TabsList = (props: TabsListProps) => {
    const ctx = useTabsContext();
    const [local, others] = splitProps(props, ["class", "className", "children"]);

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        const base = ctx.orientation() === "vertical"
            ? "flex flex-col gap-1 rounded-md bg-muted p-1"
            : "flex flex-row gap-1 rounded-md bg-muted p-1";
        return [base, userClass].filter(Boolean).join(" ");
    };

    return (
        <div class={computedClass()} role="tablist" roving={true} {...others}>
            {local.children}
        </div>
    );
};

export type TabsTriggerProps = JSX.ButtonHTMLAttributes<HTMLButtonElement> & {
    value: string;
    class?: string;
    className?: string;
};

export const TabsTrigger = (props: TabsTriggerProps) => {
    const ctx = useTabsContext();
    const [local, others] = splitProps(props, [
        "value",
        "class",
        "className",
        "disabled",
        "children",
        "onClick",
        "onFocus",
    ]);

    const isActive = () => ctx.value() === local.value;

    createEffect(() => {
        if (!ctx.isControlled() && ctx.value() == null) {
            ctx.setValue(local.value);
        }
    });

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

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        const base = "inline-flex items-center justify-center rounded-md px-3 py-1.5 text-sm";
        const stateClass = isActive()
            ? "bg-background text-foreground"
            : "text-muted-foreground hover:bg-accent hover:text-accent-foreground";
        const disabled = local.disabled ? "opacity-50" : "";
        return [base, stateClass, disabled, userClass].filter(Boolean).join(" ");
    };

    return (
        <button
            class={computedClass()}
            role="tab"
            ariaSelected={isActive()}
            ariaDisabled={local.disabled}
            disabled={local.disabled}
            onClick={handleClick}
            onFocus={handleFocus}
            {...others}
        >
            {local.children}
        </button>
    );
};

export type TabsContentProps = JSX.HTMLAttributes<HTMLDivElement> & {
    value: string;
    forceMount?: boolean;
    class?: string;
    className?: string;
};

export const TabsContent = (props: TabsContentProps) => {
    const ctx = useTabsContext();
    const [local, others] = splitProps(props, [
        "value",
        "forceMount",
        "class",
        "className",
        "children",
    ]);

    const isActive = () => ctx.value() === local.value;

    const computedClass = (hidden = false) => {
        const userClass = local.class ?? local.className ?? "";
        const base = "rounded-md border border-border p-4";
        return [base, hidden ? "hidden" : "", userClass].filter(Boolean).join(" ");
    };

    if (local.forceMount) {
        return (
            <div
                class={computedClass(!isActive())}
                role="tabpanel"
                ariaHidden={!isActive()}
                {...others}
            >
                {local.children}
            </div>
        );
    }

    return (
        <Show when={isActive()}>
            <div class={computedClass(false)} role="tabpanel" ariaHidden={false} {...others}>
                {local.children}
            </div>
        </Show>
    );
};
