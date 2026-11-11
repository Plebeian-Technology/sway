// @lat: [[service-worker-runtime-caching-and-push#Why resolveNotificationClickUrl rejects cross-origin urls]]
export const resolveNotificationClickUrl = (url: string | undefined, origin: string): string => {
    try {
        const target = new URL(url ?? "/", origin);
        return target.origin === origin ? target.pathname + target.search : "/";
    } catch {
        return "/";
    }
};
