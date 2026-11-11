// @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]

const LOCAL_HOSTNAMES = new Set(["localhost", "127.0.0.1", "[::1]", "::1", "host.docker.internal", "rustrak"]);

export const isLocalErrorCollectorDsn = (dsn: string | undefined): boolean => {
    if (!dsn) return false;

    try {
        const { hostname } = new URL(dsn);
        return LOCAL_HOSTNAMES.has(hostname.toLowerCase());
    } catch {
        return false;
    }
};

export default isLocalErrorCollectorDsn;
