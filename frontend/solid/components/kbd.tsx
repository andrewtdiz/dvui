// @ts-nocheck
import { JSX } from "solid-js";

export type KbdProps = {
    children?: JSX.Element;
    class?: string;
    className?: string;
};

export const Kbd = (props: KbdProps) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <div class={`inline-flex items-center rounded-md border border-border bg-muted px-2 py-1 text-xs font-mono text-foreground ${cls}`}>
            <p>{props.children}</p>
        </div>
    );
};
