// @ts-nocheck
export type SkeletonProps = {
    class?: string;
    className?: string;
};

export const Skeleton = (props: SkeletonProps) => {
    const cls = props.class ?? props.className ?? "";
    return (
        <div class={`bg-muted rounded-md ${cls}`} />
    );
};
