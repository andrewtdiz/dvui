// @ts-nocheck
import { Show, splitProps, JSX } from "solid-js";

export type GroupBoxProps = {
    title?: string;
    description?: string;
    class?: string;
    className?: string;
    children?: JSX.Element;
};

export const GroupBox = (props: GroupBoxProps) => {
    const [local, others] = splitProps(props, ["title", "description", "class", "className", "children"]);

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["flex flex-col gap-3 rounded-md border border-border p-4", userClass].filter(Boolean).join(" ");
    };

    const headerClass = () => "flex flex-col gap-1";

    return (
        <div class={computedClass()} {...others}>
            <Show when={local.title || local.description}>
                <div class={headerClass()}>
                    <Show when={local.title}>
                        <p class="text-sm text-foreground">{local.title}</p>
                    </Show>
                    <Show when={local.description}>
                        <p class="text-xs text-muted-foreground">{local.description}</p>
                    </Show>
                </div>
            </Show>
            {local.children}
        </div>
    );
};
