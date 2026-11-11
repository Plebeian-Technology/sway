// @lat: [[safe-external-href-check#Why isSafeExternalHref exists]]
export const isSafeExternalHref = (path: unknown): boolean => {
    if (typeof path !== "string" || path.trim().length === 0) {
        return false;
    }
    try {
        const url = new URL(path, window.location.origin);
        return url.protocol === "http:" || url.protocol === "https:";
    } catch {
        return false;
    }
};

// @lat: [[news-web-links#URL scheme safety and external navigation]]
export const isSafeUrl = (rawUrl: unknown): boolean => {
    if (typeof rawUrl !== "string" || rawUrl.trim().length === 0) {
        return false;
    }
    try {
        const parsed = new URL(rawUrl.trim());
        if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
            return false;
        }
        if (!parsed.hostname || parsed.hostname.trim() === "") {
            return false;
        }
        if (parsed.username || parsed.password) {
            return false;
        }
        return true;
    } catch {
        return false;
    }
};
