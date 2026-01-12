// @ts-nocheck
import { mergeProps, splitProps, JSX } from "solid-js";

export type ButtonVariant = "default" | "destructive" | "outline" | "secondary" | "ghost" | "link";
export type ButtonSize = "default" | "sm" | "lg" | "icon";

export type ButtonProps = JSX.ButtonHTMLAttributes<HTMLButtonElement> & {
    variant?: ButtonVariant;
    size?: ButtonSize;
    class?: string;
    className?: string;
};

// Map variants to classes that the Zig Tailwind parser supports
// Using shadcn semantic colors: primary, secondary, destructive, accent, muted, etc.
const buttonVariantClasses: Record<ButtonVariant, string> = {
    default: "bg-primary text-primary-foreground hover:bg-neutral-300",
    destructive: "bg-destructive text-destructive-foreground hover:bg-red-500",
    outline: "border border-input bg-transparent text-foreground hover:bg-accent hover:text-accent-foreground",
    secondary: "bg-secondary text-secondary-foreground hover:bg-neutral-800",
    ghost: "bg-transparent text-foreground hover:bg-accent hover:text-accent-foreground",
    link: "bg-transparent text-foreground",
};

const buttonSizeClasses: Record<ButtonSize, string> = {
    default: "h-10 px-4 py-2",
    sm: "h-9 px-3 rounded-md",
    lg: "h-11 px-8 rounded-md",
    icon: "h-10 w-10",
};

export const Button = (props: ButtonProps) => {
    const [local, others] = splitProps(props, ["variant", "size", "class", "children"]);

    const merged = mergeProps(
        { variant: "default" as ButtonVariant, size: "default" as ButtonSize },
        local
    );

    const computedClass = () => {
        const userClass = local.class ?? (props as any).className ?? "";
        return [
            // Base styles
            "inline-flex items-center justify-center rounded-md text-sm",
            buttonVariantClasses[merged.variant],
            buttonSizeClasses[merged.size],
            // Add disabled opacity through class
            props.disabled ? "opacity-50" : "",
            userClass
        ].filter(Boolean).join(" ");
    };

    return (
        <button
            class={computedClass()}
            {...others}
        >
            {local.children}
        </button>
    );
};
