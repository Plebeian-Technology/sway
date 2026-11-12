// @lat: [[mobile-bill-surface-components-design#HearingTestimonySection#DEFAULT_ALLOWED_HOSTS]]
export const DEFAULT_ALLOWED_HOSTS: readonly string[] = Object.freeze([
    "mgaleg.maryland.gov",
    "legistar.com",
    "legislature.maryland.gov",
    "congress.gov",
    "lims.dccouncil.gov",
    "lims.dccouncil.us",
    "cityclerk.lacity.org",
    "clkrep.lacity.org",
    "legislative.maryland.gov",
]);

export const OFFICIAL_SOURCE_HOSTS_BY_LOCALE: Record<string, readonly string[]> = {
    "baltimore-maryland-united_states": Object.freeze(["legistar.com"]),
    "baltimore_county-maryland-united_states": Object.freeze(["baltimorecountymd.gov"]),
    "maryland-maryland-united_states": Object.freeze([
        "mgaleg.maryland.gov",
        "legislature.maryland.gov",
        "legislative.maryland.gov",
    ]),
    "congress-congress-united_states": Object.freeze(["congress.gov"]),
    "washington-district_of_columbia-united_states": Object.freeze(["lims.dccouncil.gov", "lims.dccouncil.us"]),
    "los_angeles-california-united_states": Object.freeze(["cityclerk.lacity.org", "clkrep.lacity.org"]),
};

export function getOfficialSourceHosts(
    swayLocaleSlug?: string,
    additionalHosts?: readonly string[] | null,
): readonly string[] {
    const hosts = new Set<string>(DEFAULT_ALLOWED_HOSTS);
    if (swayLocaleSlug && OFFICIAL_SOURCE_HOSTS_BY_LOCALE[swayLocaleSlug]) {
        for (const host of OFFICIAL_SOURCE_HOSTS_BY_LOCALE[swayLocaleSlug]) {
            hosts.add(host);
        }
    }
    if (additionalHosts) {
        for (const host of additionalHosts) {
            hosts.add(host);
        }
    }
    return Array.from(hosts);
}

export function isSafeBillLink(
    url: string | undefined | null,
    allowedHosts: Iterable<string> = DEFAULT_ALLOWED_HOSTS,
): boolean {
    if (!url) return false;
    try {
        const parsed = new URL(url);
        if (parsed.protocol !== "https:") return false;
        const hostname = parsed.hostname.toLowerCase();
        return Array.from(allowedHosts).some((h) => {
            const host = h.toLowerCase();
            return hostname === host || hostname.endsWith("." + host);
        });
    } catch {
        return false;
    }
}
