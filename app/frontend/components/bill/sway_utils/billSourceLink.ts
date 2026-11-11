// @lat: [[unlinked-bill-presentation#Separation of URL safety from link validity]]

export function hasValidSourceLink(link?: string | null, genericPortalUrls?: string[]): boolean {
    if (!link || typeof link !== "string" || link.trim() === "") return false;

    try {
        const parsed = new URL(link.trim());
        if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return false;

        const hostname = parsed.hostname.toLowerCase();
        const pathname = parsed.pathname.toLowerCase().replace(/\/+$/, "");

        if (genericPortalUrls && genericPortalUrls.length > 0) {
            for (const portalUrl of genericPortalUrls) {
                if (!portalUrl || typeof portalUrl !== "string") continue;
                try {
                    const portal = new URL(portalUrl.trim());
                    const portalHost = portal.hostname.toLowerCase();
                    const portalPath = portal.pathname.toLowerCase().replace(/\/+$/, "");
                    if (hostname === portalHost && pathname === portalPath) {
                        return false;
                    }
                } catch {}
            }
        }

        return true;
    } catch {
        return false;
    }
}
