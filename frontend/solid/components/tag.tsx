// @ts-nocheck
import { JSX } from "solid-js";

export type TagProps = {
    children?: JSX.Element;
    class?: string;
    className?: string;
};

export const Tag = (props: TagProps) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <div class={`inline-flex items-center rounded-md border border-border bg-muted px-2 py-1 text-xs text-muted-foreground ${cls}`}>
            <p>{props.children}</p>
        </div>
    );
};
