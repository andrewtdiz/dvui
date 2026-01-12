export const decodeTextPayload = (event: any) => {
    if (event?.target?.value !== undefined) {
        return String(event.target.value);
    }
    if (event?.detail !== undefined) {
        return String(event.detail);
    }
    if (event instanceof Uint8Array) {
        return new TextDecoder().decode(event);
    }
    return String(event ?? "");
};

export const normalizeKeyPayload = (event: any) => {
    const raw = event instanceof Uint8Array
        ? new TextDecoder().decode(event)
        : event?.key ?? event?.detail ?? event;
    if (raw == null) return "";
    const value = String(raw);
    const lowered = value.toLowerCase();
    switch (lowered) {
        case "arrowup":
            return "up";
        case "arrowdown":
            return "down";
        case "arrowleft":
            return "left";
        case "arrowright":
            return "right";
        case "pageup":
        case "page_up":
            return "page_up";
        case "pagedown":
        case "page_down":
            return "page_down";
        default:
            return lowered;
    }
};
