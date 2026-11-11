import { notify } from "app/frontend/sway_utils";
import { parseRetryAfter, throttleCopy } from "app/frontend/sway_utils/rate_limit";

export type ThrottleScope = "sign_in" | "sign_up" | "phone" | "email";

export const handleThrottledError = (
    error: unknown,
    scope: ThrottleScope,
    onThrottled?: (until: Date | null) => void,
): boolean => {
    const response =
        error && typeof error === "object" && "response" in error
            ? ((error as { response?: Response }).response ?? null)
            : null;

    if (response?.status === 429) {
        const { throttledUntil, waitLabel } = parseRetryAfter(response);
        notify({ level: "error", title: throttleCopy(scope, waitLabel) });
        onThrottled?.(throttledUntil);
        return true;
    }

    return false;
};
