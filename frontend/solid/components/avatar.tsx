// @ts-nocheck
import { Image } from "./image";

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
