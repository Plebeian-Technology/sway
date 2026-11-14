export interface RateLimitResult {
    throttledUntil: Date | null;
    waitLabel: string | null;
}

// @lat: [[rate-limit-toast-spec-design#Why ThrottleResponse.headers accepts either shape]]
interface ThrottleResponse {
    status: number;
    headers?: Headers | Record<string, string> | null;
}

const readHeader = (headers: ThrottleResponse["headers"], name: string): string | null => {
    if (!headers) {
        return null;
    }
    if (typeof (headers as Headers).get === "function") {
        return (headers as Headers).get(name);
    }
    const record = headers as Record<string, string>;
    return record[name] ?? record[name.toLowerCase()] ?? null;
};

const waitLabelFor = (seconds: number): string => {
    if (seconds < 60) {
        return `${seconds} seconds`;
    }
    if (seconds < 3600) {
        return `${Math.ceil(seconds / 60)} minutes`;
    }
    const hours = Math.round(seconds / 3600);
    return hours === 1 ? "about an hour" : `about ${hours} hours`;
};

export function parseRetryAfter(response: ThrottleResponse | null): RateLimitResult {
    if (!response || response.status !== 429) {
        return { throttledUntil: null, waitLabel: null };
    }
    const header = readHeader(response.headers, "Retry-After");
    if (!header) {
        return { throttledUntil: new Date(Date.now() + 60_000), waitLabel: null };
    }
    const seconds = parseInt(header, 10);
    if (isNaN(seconds) || seconds < 0) {
        return { throttledUntil: new Date(Date.now() + 60_000), waitLabel: null };
    }
    return {
        throttledUntil: new Date(Date.now() + seconds * 1000),
        waitLabel: waitLabelFor(seconds),
    };
}

export function throttleCopy(scope: "sign_in" | "sign_up" | "phone" | "email", waitLabel: string | null): string {
    const subject = scope === "sign_in" ? "sign-in" : scope === "sign_up" ? "sign-up" : "verification";
    return waitLabel
        ? `Too many ${subject} attempts. Please wait ${waitLabel} before trying again.`
        : `Too many ${subject} attempts. Please try again later.`;
}
