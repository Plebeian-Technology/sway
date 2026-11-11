// @lat: [[news-mobile-citations#Mobile summary citations#Citation URL safety validation]]

export function isSafeCitationUrl(url: string | null | undefined): boolean {
    if (!url || typeof url !== "string") return false;
    const trimmed = url.trim();
    if (!trimmed) return false;
    try {
        const parsed = new URL(trimmed);
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
}
