// @ts-nocheck
import { JSX } from "solid-js";

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
