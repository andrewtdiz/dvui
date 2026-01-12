// @ts-nocheck
import { splitProps } from "solid-js";

export type IconKind = "auto" | "svg" | "tvg" | "image" | "raster" | "glyph";

export type IconProps = {
    src?: string;
    kind?: IconKind;
    glyph?: string;
    class?: string;
    className?: string;
};

export const Icon = (props: IconProps) => {
    const [local, others] = splitProps(props, ["src", "kind", "glyph", "class", "className"]);

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        return ["h-4 w-4", userClass].filter(Boolean).join(" ");
    };

    return (
        <icon
            class={computedClass()}
            src={local.src}
            iconKind={local.kind ?? "auto"}
            iconGlyph={local.glyph}
            {...others}
        />
    );
};
