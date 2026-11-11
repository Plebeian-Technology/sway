// @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]

import { Platform } from "react-native";

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1", "10.0.2.2"]);

// @lat: [[local-error-reporting-design#Why local_error_dsn.ts does not use new URL to parse the DSN (mobile)]]
const DSN_PARTS = /^(https?:\/\/[^@/]+@)([^:/]+)(.*)$/;

const hostOf = (dsn: string): string | null => DSN_PARTS.exec(dsn)?.[2]?.toLowerCase() ?? null;

export const isLocalErrorCollectorDsn = (dsn: string | undefined): boolean => {
    if (!dsn) return false;
    const host = hostOf(dsn);
    return host === null ? false : LOCAL_HOSTS.has(host);
};

// @lat: [[local-error-reporting-design#Why SwayLocalErrorDsn refuses rather than warns]]
export const dsnForThisPlatform = (dsn: string): string => {
    if (Platform.OS !== "android") return dsn;

    const parts = DSN_PARTS.exec(dsn);
    if (!parts) return dsn;

    const [, prefix, host, rest] = parts;
    if (host.toLowerCase() !== "localhost" && host !== "127.0.0.1") return dsn;

    return `${prefix}10.0.2.2${rest}`;
};
