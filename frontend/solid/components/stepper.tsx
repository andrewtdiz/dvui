// @ts-nocheck
import { createSignal, Show, splitProps, JSX } from "solid-js";

export type StepperOrientation = "horizontal" | "vertical";

export type StepperStep = {
    title: JSX.Element;
    description?: JSX.Element;
    disabled?: boolean;
};

export type StepperProps = {
    steps: StepperStep[];
    value?: number;
    defaultValue?: number;
    onChange?: (value: number) => void;
    orientation?: StepperOrientation;
    class?: string;
    className?: string;
};

export const Stepper = (props: StepperProps) => {
    const [local, others] = splitProps(props, [
        "steps",
        "value",
        "defaultValue",
        "onChange",
        "orientation",
        "class",
        "className",
    ]);

    const [internalValue, setInternalValue] = createSignal(local.defaultValue ?? 0);

    const steps = () => local.steps ?? [];

    const maxIndex = () => Math.max(0, steps().length - 1);

    const currentStep = () => {
        const raw = local.value ?? internalValue();
        const value = Number(raw);
        if (!Number.isFinite(value)) return 0;
        return Math.min(maxIndex(), Math.max(0, Math.floor(value)));
    };

    const setCurrentStep = (value: number) => {
        const next = Math.min(maxIndex(), Math.max(0, Math.floor(Number.isFinite(value) ? value : 0)));
        if (next === currentStep()) return;
        if (local.value === undefined) {
            setInternalValue(next);
        }
        local.onChange?.(next);
    };

    const orientation = () => local.orientation ?? "horizontal";

    const computedClass = () => {
        const userClass = local.class ?? local.className ?? "";
        const base = orientation() === "vertical"
            ? "flex flex-col gap-3"
            : "flex flex-row items-center gap-3";
        return [base, userClass].filter(Boolean).join(" ");
    };

    const stepState = (index: number) => {
        if (index < currentStep()) return "complete";
        if (index === currentStep()) return "active";
        return "upcoming";
    };

    const indicatorClass = (state: string, disabled: boolean) => {
        const base = "flex h-7 w-7 items-center justify-center rounded-full border text-xs";
        const stateClass = state === "complete"
            ? "bg-primary text-primary-foreground border-primary"
            : state === "active"
                ? "border-primary text-foreground"
                : "border-border text-muted-foreground";
        const disabledClass = disabled ? "opacity-50" : "";
        return [base, stateClass, disabledClass].filter(Boolean).join(" ");
    };

    const titleClass = (state: string, disabled: boolean, align: "center" | "left") => {
        const base = "text-sm";
        const stateClass = state === "upcoming" ? "text-muted-foreground" : "text-foreground";
        const disabledClass = disabled ? "opacity-50" : "";
        const alignClass = align === "center" ? "text-center" : "text-left";
        return [base, stateClass, disabledClass, alignClass].filter(Boolean).join(" ");
    };

    const descriptionClass = (disabled: boolean, align: "center" | "left") => {
        const alignClass = align === "center" ? "text-center" : "text-left";
        const disabledClass = disabled ? "opacity-50" : "";
        return ["text-xs text-muted-foreground", alignClass, disabledClass].filter(Boolean).join(" ");
    };

    const stepButtonClass = (orientationValue: StepperOrientation, disabled: boolean) => {
        const base = orientationValue === "vertical"
            ? "flex flex-row items-start gap-3"
            : "flex flex-col items-center gap-1";
        const disabledClass = disabled ? "opacity-50" : "";
        return [base, disabledClass].filter(Boolean).join(" ");
    };

    if (steps().length === 0) {
        return null;
    }

    if (orientation() === "vertical") {
        return (
            <div class={computedClass()} {...others}>
                {steps().map((step, index) => {
                    const state = stepState(index);
                    const disabled = Boolean(step.disabled);
                    const isLast = index === steps().length - 1;

                    return (
                        <button
                            class={stepButtonClass("vertical", disabled)}
                            onClick={() => {
                                if (disabled) return;
                                setCurrentStep(index);
                            }}
                            disabled={disabled}
                            ariaDisabled={disabled}
                            ariaSelected={state === "active"}
                        >
                            <div class="flex flex-col items-center">
                                <div class={indicatorClass(state, disabled)}>
                                    {state === "complete" ? "✓" : index + 1}
                                </div>
                                <Show when={!isLast}>
                                    <div class="h-6 w-px bg-border" />
                                </Show>
                            </div>
                            <div class="flex flex-col gap-1">
                                <p class={titleClass(state, disabled, "left")}>{step.title}</p>
                                <Show when={step.description}>
                                    <p class={descriptionClass(disabled, "left")}>{step.description}</p>
                                </Show>
                            </div>
                        </button>
                    );
                })}
            </div>
        );
    }

    return (
        <div class={computedClass()} {...others}>
            {steps().map((step, index) => {
                const state = stepState(index);
                const disabled = Boolean(step.disabled);
                const isLast = index === steps().length - 1;

                return (
                    <div class="flex flex-row items-center gap-3">
                        <button
                            class={stepButtonClass("horizontal", disabled)}
                            onClick={() => {
                                if (disabled) return;
                                setCurrentStep(index);
                            }}
                            disabled={disabled}
                            ariaDisabled={disabled}
                            ariaSelected={state === "active"}
                        >
                            <div class={indicatorClass(state, disabled)}>
                                {state === "complete" ? "✓" : index + 1}
                            </div>
                            <div class="flex flex-col items-center gap-1">
                                <p class={titleClass(state, disabled, "center")}>{step.title}</p>
                                <Show when={step.description}>
                                    <p class={descriptionClass(disabled, "center")}>{step.description}</p>
                                </Show>
                            </div>
                        </button>
                        <Show when={!isLast}>
                            <div class="h-px w-8 bg-border" />
                        </Show>
                    </div>
                );
            })}
        </div>
    );
};
