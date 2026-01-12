// @ts-nocheck
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
