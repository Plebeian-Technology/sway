// @lat: [[sway-error-scrubber-design#Why the scrubber exists]]

import RULES from "../../../app/frontend/sway_constants/errorScrubRules.json";

// @lat: [[sway-error-scrubber-design#Why the rules table has three readers]]
const REDACTIONS: { label: string; pattern: RegExp }[] = RULES.redactions.map(({ label, pattern }) => ({
    label,
    pattern: new RegExp(pattern, "g"),
}));

const MAX_STRING_LENGTH = RULES.maxStringLength;
const MAX_DEPTH = RULES.maxDepth;

const DROPPED_KEYS = new Set<string>(RULES.droppedKeys);
const PRESERVED_KEYS = new Set<string>(RULES.preservedKeys);

// @lat: [[sway-error-scrubber-design#Why scrubString (mobile) caps a huge value before redacting, not after]]
export const scrubString = (value: string): string => {
    const capped =
        value.length > MAX_STRING_LENGTH
            ? `${value.slice(0, MAX_STRING_LENGTH)}…[truncated ${value.length - MAX_STRING_LENGTH} chars]`
            : value;

    return REDACTIONS.reduce((text, { label, pattern }) => text.replace(pattern, label), capped);
};

// @lat: [[sway-error-scrubber-design#Why dropped() preserves type in scrub_error_event.ts]]
const dropped = (item: unknown): unknown => {
    if (Array.isArray(item)) return [];
    if (item !== null && typeof item === "object") return {};
    return "[FILTERED]";
};

const scrubEntry = (key: string, item: unknown, depth: number, seen: Set<object>): unknown => {
    const name = key.toLowerCase();
    if (DROPPED_KEYS.has(name)) return dropped(item);
    if (PRESERVED_KEYS.has(name)) return item;
    return scrubUnknown(item, depth + 1, seen);
};

const scrubUnknown = (value: unknown, depth: number, seen: Set<object>): unknown => {
    if (typeof value === "string") return scrubString(value);
    if (value === null || typeof value !== "object") return value;
    if (depth >= MAX_DEPTH) return "[FILTERED_TOO_DEEP]";

    // @lat: [[sway-error-scrubber-design#Why seen tracks only the active path during scrubbing]]
    if (seen.has(value)) return "[FILTERED_CIRCULAR]";
    seen.add(value);

    try {
        if (Array.isArray(value)) return value.map((item) => scrubUnknown(item, depth + 1, seen));

        return Object.fromEntries(
            Object.entries(value).map(([key, item]) => [key, scrubEntry(key, item, depth, seen)]),
        );
    } finally {
        seen.delete(value);
    }
};

// @lat: [[error-scrubber-empty-fingerprint-bug#Why the scrub-error-event test calls this Android-only]]
export const scrubErrorEvent = <T>(event: T): T => {
    const scrubbed = scrubUnknown(event, 0, new Set()) as T;
    const withFingerprint = scrubbed as { fingerprint?: unknown };

    if (Array.isArray(withFingerprint.fingerprint) && withFingerprint.fingerprint.length === 0) {
        delete withFingerprint.fingerprint;
    }

    return scrubbed;
};

export default scrubErrorEvent;
