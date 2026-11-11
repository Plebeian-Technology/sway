export interface PushPayload {
    title?: string;
    body?: string;
    icon?: string;
    // @lat: [[service-worker-runtime-caching-and-push#Why data:{url} is passed through the push notification]]
    data?: unknown;
}

// @lat: [[service-worker-runtime-caching-and-push#Why parsePushPayload and resolveNotificationClickUrl are separate plain functions]]
export const parsePushPayload = (text: string): PushPayload | null => {
    try {
        const parsed: unknown = JSON.parse(text);
        if (parsed !== null && typeof parsed === "object") {
            return parsed as PushPayload;
        }
        return null;
    } catch {
        return null;
    }
};
