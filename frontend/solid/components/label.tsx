// @ts-nocheck
import { JSX } from "solid-js";

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
