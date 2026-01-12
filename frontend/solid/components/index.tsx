// @ts-nocheck
import { createEffect, createSignal, Show, mergeProps, JSX, splitProps } from "solid-js";

// ============================================================================
// Button Component (shadcn/ui style)
// ============================================================================

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

// ============================================================================
// Checkbox Component  
// Uses a button element for proper native click handling
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
        const base = isChecked()
            ? "bg-primary text-primary-foreground border border-primary"
            : "bg-transparent border border-input";
        const size = "h-4 w-4 rounded-sm";
        const disabled = props.disabled ? "opacity-50" : "";
        return `flex items-center justify-center ${size} ${base} ${disabled}`;
    };

    // Use text symbol that's always present to avoid DVUI rendering "button" as text
    const checkSymbol = () => isChecked() ? "✓" : " ";

    return (
        <div class={`flex items-center gap-2 ${props.class ?? ""}`}>
            <button class={boxClasses()} onClick={handleClick} disabled={props.disabled}>
                <p class="text-foreground text-xs">{checkSymbol()}</p>
            </button>
            <Show when={props.label}>
                <p class={`text-sm text-foreground ${props.disabled ? "opacity-50" : ""}`}>{props.label}</p>
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

// ============================================================================
// Progress Component
// Uses nested divs for track and fill with inline style for precise control
// ============================================================================
export type ProgressProps = {
    value?: number;  // 0-100
    max?: number;
    class?: string;
};

export const Progress = (props: ProgressProps) => {
    const merged = mergeProps({ value: 0, max: 100 }, props);

    const percentage = () => Math.min(100, Math.max(0, (merged.value / merged.max) * 100));

    return (
        <div class={`h-2 w-full overflow-hidden rounded-full bg-secondary ${props.class ?? ""}`}>
            <div
                class="h-full bg-primary"
                style={{ width: `${percentage()}%` }}
            />
        </div>
    );
};

// ============================================================================
// Input Component
// Uses native <input> tag - receives input events from native backend
// ============================================================================
export type InputProps = {
    value?: string;
    placeholder?: string;
    onChange?: (value: string) => void;
    disabled?: boolean;
    class?: string;
};

export const Input = (props: InputProps) => {
    const [localValue, setLocalValue] = createSignal(props.value ?? "");

    // Sync with external value prop
    const displayValue = () => props.value !== undefined ? props.value : localValue();

    const handleInput = (e: any) => {
        // Handle both DOM-style events and native events
        let newValue: string;
        if (e?.target?.value !== undefined) {
            newValue = e.target.value;
        } else if (e?.detail !== undefined) {
            newValue = e.detail;
        } else if (e instanceof Uint8Array) {
            // Native event payload - decode as text
            newValue = new TextDecoder().decode(e);
        } else {
            newValue = String(e ?? "");
        }

        setLocalValue(newValue);
        props.onChange?.(newValue);
    };

    const computedClass = () => {
        const disabled = props.disabled ? "opacity-50" : "";
        return `h-10 rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground ${disabled} ${props.class ?? ""}`;
    };

    return (
        <input
            class={computedClass()}
            value={displayValue()}
            placeholder={props.placeholder}
            onInput={handleInput}
            disabled={props.disabled}
        />
    );
};

// ============================================================================
// Card Component
// Basic card container with shadcn styling
// ============================================================================
export type CardProps = {
    children?: JSX.Element;
    class?: string;
    className?: string;
};

// Card with fixed width using w-96 (384px) - DVUI parses width as value * 4px
export const Card = (props: CardProps) => {
    return (
        <div class="rounded-lg border border-border bg-neutral-900 text-foreground p-6 w-96">
            {props.children}
        </div>
    );
};

// CardHeader - row layout with title/description on left, action on right
export const CardHeader = (props: { children?: JSX.Element; class?: string; className?: string }) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <div class={`flex flex-row justify-between items-start pb-4 ${cls}`}>
            {props.children}
        </div>
    );
};

// CardHeaderContent - wrapper for title and description
export const CardHeaderContent = (props: { children?: JSX.Element; class?: string; className?: string }) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <div class={`flex flex-col gap-1 ${cls}`}>
            {props.children}
        </div>
    );
};

export const CardTitle = (props: { children?: JSX.Element; class?: string; className?: string }) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <p class={`text-lg text-foreground ${cls}`}>
            {props.children}
        </p>
    );
};

export const CardDescription = (props: { children?: JSX.Element; class?: string; className?: string }) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <p class={`text-sm text-muted-foreground ${cls}`}>
            {props.children}
        </p>
    );
};

// CardAction - renders inline in the header row
export const CardAction = (props: { children?: JSX.Element; class?: string; className?: string }) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <div class={cls}>
            {props.children}
        </div>
    );
};

export const CardContent = (props: { children?: JSX.Element; class?: string; className?: string }) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <div class={`gap-4 ${cls}`}>
            {props.children}
        </div>
    );
};

export const CardFooter = (props: { children?: JSX.Element; class?: string; className?: string }) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <div class={`gap-2 pt-4 ${cls}`}>
            {props.children}
        </div>
    );
};

// ============================================================================
// Label Component
// Simple styled label
// ============================================================================
export type LabelProps = {
    children?: JSX.Element;
    class?: string;
    className?: string;
    for?: string;
    htmlFor?: string;
};

export const Label = (props: LabelProps) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <p class={`text-sm text-foreground ${cls}`}>
            {props.children}
        </p>
    );
};

// ============================================================================
// Separator Component
// Horizontal or vertical divider
// ============================================================================
export type SeparatorProps = {
    orientation?: "horizontal" | "vertical";
    class?: string;
};

export const Separator = (props: SeparatorProps) => {
    const isHorizontal = () => (props.orientation ?? "horizontal") === "horizontal";

    const separatorClass = () => {
        if (isHorizontal()) {
            return `h-px w-full bg-border ${props.class ?? ""}`;
        }
        return `h-full w-px bg-border ${props.class ?? ""}`;
    };

    return <div class={separatorClass()} />;
};

// ============================================================================
// Switch Component
// Toggle switch with on/off state - uses button for proper click handling
// ============================================================================
export type SwitchProps = {
    checked?: boolean;
    defaultChecked?: boolean;
    onChange?: (checked: boolean) => void;
    disabled?: boolean;
    class?: string;
};

export const Switch = (props: SwitchProps) => {
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

    const trackClass = () => {
        const base = isChecked() ? "bg-primary" : "bg-input";
        const disabled = props.disabled ? "opacity-50" : "";
        return `flex flex-row items-center h-6 w-11 rounded-full ${base} ${disabled} ${props.class ?? ""}`;
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
        <button class={trackClass()} onClick={handleClick} disabled={props.disabled}>
            <div class={spacerClass()}> </div>
            <div class={thumbClass()}> </div>
        </button>
    );
};

// ============================================================================
// Icon Component
// ============================================================================
export type IconKind = "auto" | "svg" | "tvg" | "image" | "raster" | "glyph";

export type IconProps = {
    src?: string;
    kind?: IconKind;
    glyph?: string;
    class?: string;
    className?: string;
};

export const Icon = (props: IconProps) => {
    const [local, others] = splitProps(props, ["src", "kind", "glyph", "class", "className"]);

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["h-4 w-4", userClass].filter(Boolean).join(" ");
    };

    return (
        <icon
            class={computedClass()}
            src={local.src}
            iconKind={local.kind ?? "auto"}
            iconGlyph={local.glyph}
            {...others}
        />
    );
};

// ============================================================================
// Image Component
// Includes optional fallback content when src is missing or fails to load
// ============================================================================
export type ImageProps = JSX.ImgHTMLAttributes<HTMLImageElement> & {
    fallback?: JSX.Element;
    class?: string;
    className?: string;
};

export const Image = (props: ImageProps) => {
    const [imageError, setImageError] = createSignal(false);
    const [local, others] = splitProps(props, ["src", "alt", "fallback", "class", "className", "onError"]);

    createEffect(() => {
        local.src;
        setImageError(false);
    });

    const baseClass = () => local.class ?? local.className ?? "";
    const hasSrc = () => typeof local.src === "string" && local.src.length > 0;
    const showFallback = () => !hasSrc() || imageError();

    const fallbackBase = () => local.fallback
        ? "flex items-center justify-center"
        : "flex items-center justify-center bg-muted text-muted-foreground";
    const fallbackClass = () => [fallbackBase(), baseClass()].filter(Boolean).join(" ");
    const fallbackContent = () => local.fallback ?? <p class="text-xs">Image</p>;

    const handleError = (event: unknown) => {
        setImageError(true);
        if (typeof local.onError === "function") {
            local.onError(event as any);
        }
    };

    return (
        <Show when={!showFallback()} fallback={<div class={fallbackClass()}>{fallbackContent()}</div>}>
            <img
                class={baseClass()}
                src={local.src}
                alt={local.alt ?? ""}
                aria-label={local.alt ?? undefined}
                onError={handleError}
                {...others}
            />
        </Show>
    );
};

// ============================================================================
// Avatar Component
// Display user avatar with fallback
// ============================================================================
export type AvatarProps = {
    src?: string;
    alt?: string;
    fallback?: string;
    class?: string;
    className?: string;
};

export const Avatar = (props: AvatarProps) => {
    const fallbackText = () => {
        if (props.fallback && props.fallback.length > 0) return props.fallback;
        if (props.alt && props.alt.length > 0) return props.alt.slice(0, 2).toUpperCase();
        return "?";
    };

    const wrapperClass = () => {
        const userClass = props.class ?? props.className ?? "";
        return `flex h-10 w-10 items-center justify-center rounded-full bg-muted overflow-hidden ${userClass}`;
    };

    return (
        <div class={wrapperClass()}>
            <Image
                src={props.src}
                alt={props.alt}
                class="h-full w-full"
                fallback={<p class="text-sm text-muted-foreground">{fallbackText()}</p>}
            />
        </div>
    );
};

// ============================================================================
// Skeleton Component
// Loading placeholder with animation
// ============================================================================
export type SkeletonProps = {
    class?: string;
};

export const Skeleton = (props: SkeletonProps) => {
    return (
        <div class={`bg-muted rounded-md ${props.class ?? ""}`} />
    );
};

// ============================================================================
// Textarea Component
// Multi-line text input - receives input events from native backend
// ============================================================================
export type TextareaProps = {
    value?: string;
    placeholder?: string;
    onChange?: (value: string) => void;
    disabled?: boolean;
    rows?: number;
    class?: string;
};

export const Textarea = (props: TextareaProps) => {
    const [localValue, setLocalValue] = createSignal(props.value ?? "");

    const displayValue = () => props.value !== undefined ? props.value : localValue();

    const handleInput = (e: any) => {
        let newValue: string;
        if (e?.target?.value !== undefined) {
            newValue = e.target.value;
        } else if (e?.detail !== undefined) {
            newValue = e.detail;
        } else if (e instanceof Uint8Array) {
            newValue = new TextDecoder().decode(e);
        } else {
            newValue = String(e ?? "");
        }

        setLocalValue(newValue);
        props.onChange?.(newValue);
    };

    const computedClass = () => {
        const disabled = props.disabled ? "opacity-50" : "";
        return `flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground ${disabled} ${props.class ?? ""}`;
    };

    return (
        <textarea
            class={computedClass()}
            value={displayValue()}
            placeholder={props.placeholder}
            rows={props.rows ?? 3}
            onInput={handleInput}
            disabled={props.disabled}
        />
    );
};
