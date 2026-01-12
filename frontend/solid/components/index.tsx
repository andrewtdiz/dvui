// @ts-nocheck
import { createSignal, Show, mergeProps, JSX, splitProps } from "solid-js";

// ============================================================================
// Button Component (shadcn/ui style)
// ============================================================================

export type ButtonVariant = "default" | "destructive" | "outline" | "secondary" | "ghost" | "link";
export type ButtonSize = "default" | "sm" | "lg" | "icon";

export type ButtonProps = JSX.ButtonHTMLAttributes<HTMLButtonElement> & {
    variant?: ButtonVariant;
    size?: ButtonSize;
    class?: string;
};

const buttonVariantClasses: Record<ButtonVariant, string> = {
    default: "bg-primary text-primary-foreground hover:bg-primary/90",
    destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
    outline: "border border-input bg-background hover:bg-accent hover:text-accent-foreground",
    secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/80",
    ghost: "hover:bg-accent hover:text-accent-foreground",
    link: "text-primary underline-offset-4 hover:underline",
};

const buttonSizeClasses: Record<ButtonSize, string> = {
    default: "h-10 px-4 py-2",
    sm: "h-9 rounded-md px-3",
    lg: "h-11 rounded-md px-8",
    icon: "h-10 w-10",
};

export const Button = (props: ButtonProps) => {
    const [local, others] = splitProps(props, ["variant", "size", "class", "children"]);

    const merged = mergeProps(
        { variant: "default" as ButtonVariant, size: "default" as ButtonSize },
        local
    );

    const computedClass = () => {
        return [
            // Base styles
            "inline-flex items-center justify-center rounded-md text-sm font-medium disabled:opacity-50",
            buttonVariantClasses[merged.variant],
            buttonSizeClasses[merged.size],
            local.class
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

// ============================================================================
// Checkbox Component  
// Uses styled div with click handler for toggle behavior
// ============================================================================
export type CheckboxProps = {
    checked?: boolean;
    defaultChecked?: boolean;
    onChange?: (checked: boolean) => void;
    disabled?: boolean;
    label?: string;
    class?: string;
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

    const boxClasses = () => {
        const base = "flex items-center justify-center w-5 h-5 rounded";
        const checked = isChecked() ? "bg-blue-600" : "bg-gray-700";
        const disabled = props.disabled ? "opacity-50" : "";
        return `${base} ${checked} ${disabled}`;
    };

    return (
        <div class={`flex items-center gap-2 ${props.class ?? ""}`} onClick={handleClick}>
            <div class={boxClasses()}>
                <Show when={isChecked()}>
                    <p class="text-white text-xs">✓</p>
                </Show>
            </div>
            <Show when={props.label}>
                <p class="text-sm text-gray-300">{props.label}</p>
            </Show>
        </div>
    );
};

// ============================================================================
// Alert Component
// Uses div container with styled content
// ============================================================================
export type AlertVariant = "default" | "destructive" | "success" | "warning";

export type AlertProps = {
    variant?: AlertVariant;
    title?: string;
    children?: JSX.Element;
    class?: string;
};

const alertVariantClasses: Record<AlertVariant, string> = {
    default: "bg-gray-800 text-gray-300",
    destructive: "bg-red-900 text-red-200",
    success: "bg-green-900 text-green-200",
    warning: "bg-amber-900 text-amber-200",
};

export const Alert = (props: AlertProps) => {
    const merged = mergeProps({ variant: "default" as AlertVariant }, props);

    const computedClass = () => {
        const variant = alertVariantClasses[merged.variant];
        return `flex flex-col gap-1 p-4 rounded-md ${variant} ${props.class ?? ""}`;
    };

    return (
        <div class={computedClass()}>
            <Show when={props.title}>
                <p class="text-sm">{props.title}</p>
            </Show>
            <p class="text-sm">{props.children}</p>
        </div>
    );
};

// ============================================================================
// Badge Component
// ============================================================================
export type BadgeVariant = "default" | "secondary" | "destructive" | "outline";

export type BadgeProps = {
    variant?: BadgeVariant;
    children?: JSX.Element;
    class?: string;
};

const badgeVariantClasses: Record<BadgeVariant, string> = {
    default: "bg-blue-600 text-white",
    secondary: "bg-gray-700 text-gray-300",
    destructive: "bg-red-600 text-white",
    outline: "bg-gray-800 text-gray-300",
};

export const Badge = (props: BadgeProps) => {
    const merged = mergeProps({ variant: "default" as BadgeVariant }, props);

    const computedClass = () => {
        const variant = badgeVariantClasses[merged.variant];
        return `flex items-center justify-center px-2 py-1 rounded-full text-xs ${variant} ${props.class ?? ""}`;
    };

    return (
        <div class={computedClass()}>
            <p>{props.children}</p>
        </div>
    );
};

// ============================================================================
// Progress Component
// Uses nested divs for track and fill
// ============================================================================
export type ProgressProps = {
    value?: number;  // 0-100
    max?: number;
    class?: string;
};

export const Progress = (props: ProgressProps) => {
    const merged = mergeProps({ value: 0, max: 100 }, props);

    const percentage = () => Math.min(100, Math.max(0, (merged.value / merged.max) * 100));

    // Calculate fill width as pixels (assuming a standard 200px width container)
    const fillWidth = () => `w-${Math.round(percentage() * 2)}`;

    return (
        <div class={`flex w-full h-2 bg-gray-700 rounded-full overflow-hidden ${props.class ?? ""}`}>
            <div class={`bg-blue-600 h-2 rounded-full ${fillWidth()}`} />
        </div>
    );
};

// ============================================================================
// Input Component
// Uses native <input> tag - maps to dvui input handling
// ============================================================================
export type InputProps = {
    value?: string;
    placeholder?: string;
    onChange?: (value: string) => void;
    disabled?: boolean;
    class?: string;
};

export const Input = (props: InputProps) => {
    const computedClass = () => {
        const disabled = props.disabled ? "opacity-50" : "";
        return `bg-gray-800 text-gray-300 px-3 py-2 rounded-md text-sm ${disabled} ${props.class ?? ""}`;
    };

    return (
        <input
            class={computedClass()}
            value={props.value ?? ""}
            onInput={(e: any) => props.onChange?.(e.target?.value ?? "")}
        />
    );
};
