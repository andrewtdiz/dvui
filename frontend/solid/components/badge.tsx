// @ts-nocheck
import { mergeProps, JSX } from "solid-js";

export type BadgeVariant = "default" | "secondary" | "destructive" | "outline";

export type BadgeProps = {
    variant?: BadgeVariant;
    children?: JSX.Element;
    class?: string;
};

const badgeVariantClasses: Record<BadgeVariant, string> = {
    default: "bg-primary text-primary-foreground",
    secondary: "bg-secondary text-secondary-foreground",
    destructive: "bg-destructive text-destructive-foreground",
    outline: "bg-transparent text-foreground border border-border",
};

export const Badge = (props: BadgeProps) => {
    const merged = mergeProps({ variant: "default" as BadgeVariant }, props);

    const computedClass = () => {
        const variant = badgeVariantClasses[merged.variant];
        return `inline-flex items-center rounded-full px-2 py-1 text-xs ${variant} ${props.class ?? ""}`;
    };

    return (
        <div class={computedClass()}>
            <p>{props.children}</p>
        </div>
    );
};
