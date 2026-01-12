// @ts-nocheck
import { createEffect, createSignal, Show, splitProps, JSX } from "solid-js";

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
