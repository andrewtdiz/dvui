// @ts-nocheck
import { splitProps, JSX } from "solid-js";

export type DescriptionListItem = {
    term: JSX.Element;
    description: JSX.Element;
};

export type DescriptionListProps = {
    items?: DescriptionListItem[];
    class?: string;
    className?: string;
    itemClass?: string;
    termClass?: string;
    descriptionClass?: string;
    children?: JSX.Element;
};

export const DescriptionList = (props: DescriptionListProps) => {
    const [local, others] = splitProps(props, [
        "items",
        "class",
        "className",
        "itemClass",
        "termClass",
        "descriptionClass",
        "children",
    ]);

    const listClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["flex flex-col gap-3", userClass].filter(Boolean).join(" ");
    };

    const itemClass = () => {
        const userClass = local.itemClass ?? "";
        return ["flex flex-col gap-1", userClass].filter(Boolean).join(" ");
    };

    const termClass = () => {
        const userClass = local.termClass ?? "";
        return ["text-xs text-muted-foreground", userClass].filter(Boolean).join(" ");
    };

    const descriptionClass = () => {
        const userClass = local.descriptionClass ?? "";
        return ["text-sm text-foreground", userClass].filter(Boolean).join(" ");
    };

    const renderItems = () => local.items?.map((item) => (
        <div class={itemClass()}>
            <p class={termClass()}>{item.term}</p>
            <p class={descriptionClass()}>{item.description}</p>
        </div>
    ));

    return (
        <div class={listClass()} {...others}>
            {local.items && local.items.length > 0 ? renderItems() : local.children}
        </div>
    );
};
