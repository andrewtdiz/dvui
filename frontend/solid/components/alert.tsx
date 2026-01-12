// @ts-nocheck
import { mergeProps, Show, JSX } from "solid-js";

export type AlertVariant = "default" | "destructive" | "success" | "warning";

export type AlertProps = {
    variant?: AlertVariant;
    title?: string;
    children?: JSX.Element;
    class?: string;
};

const alertVariantClasses: Record<AlertVariant, string> = {
    default: "bg-background text-foreground border border-border",
    destructive: "bg-background text-destructive border border-destructive",
    success: "bg-background text-emerald-500 border border-emerald-500",
    warning: "bg-background text-amber-500 border border-amber-500",
};

export const Alert = (props: AlertProps) => {
    const merged = mergeProps({ variant: "default" as AlertVariant }, props);

    const computedClass = () => {
        const variant = alertVariantClasses[merged.variant];
        return `flex flex-col gap-1 rounded-lg p-4 ${variant} ${props.class ?? ""}`;
    };

    return (
        <div class={computedClass()}>
            <Show when={props.title}>
                <p class="text-sm">{props.title}</p>
            </Show>
            <p class="text-sm text-muted-foreground">{props.children}</p>
        </div>
    );
};
