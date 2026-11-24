import appConfig from "../app.config";
import { DEEP_LINK_PATTERNS } from "../src/navigation/deepLinkPatterns.ts";

const build = () => appConfig({ config: { name: "Sway", slug: "sway-mobile" } } as never);

const stubbedEnv = {
    APPLE_BUNDLE_ID: "app.example.test",
    EXPO_PUBLIC_DEV_TUNNEL_HOST: "tunnel.example.test",
    SENTRY_DSN_MOBILE: "https://key@o1.ingest.us.sentry.io/1\n",
};

const originalEnv = Object.fromEntries(Object.keys(stubbedEnv).map((name) => [name, process.env[name]]));

describe("app.config.ts", () => {
    beforeEach(() => {
        Object.assign(process.env, stubbedEnv);
    });

    afterEach(() => {
        Object.entries(originalEnv).forEach(([name, value]) => {
            if (value === undefined) delete process.env[name];
            else process.env[name] = value;
        });
    });

    it("takes both platforms' app identifier from APPLE_BUNDLE_ID", () => {
        const config = build();

        expect(config.ios?.bundleIdentifier).toBe("app.example.test");
        expect(config.android?.package).toBe("app.example.test");
    });

    // @lat: [[mobile-expo-config#Deployment identifiers come from the environment#Why a missing bundle id stops the config]]
    it("refuses to resolve without APPLE_BUNDLE_ID, naming the variable and the runner", () => {
        delete process.env.APPLE_BUNDLE_ID;

        expect(build).toThrow(/APPLE_BUNDLE_ID.*with-vault-env\.sh/);
    });

    // @lat: [[mobile-expo-config#Deployment identifiers come from the environment#The dev tunnel host is claimed only when set]]
    it("claims the dev tunnel host only when one is set", () => {
        expect(build().ios?.associatedDomains).toEqual([
            "webcredentials:app.sway.vote",
            "applinks:sway.vote",
            "applinks:app.sway.vote",
            "webcredentials:tunnel.example.test?mode=developer",
            "applinks:tunnel.example.test?mode=developer",
        ]);
        expect(build().android?.intentFilters).toHaveLength(3);

        delete process.env.EXPO_PUBLIC_DEV_TUNNEL_HOST;

        expect(build().ios?.associatedDomains).toEqual([
            "webcredentials:app.sway.vote",
            "applinks:sway.vote",
            "applinks:app.sway.vote",
        ]);
        expect(build().android?.intentFilters?.map((filter) => filter.data)).toEqual([
            expect.arrayContaining([expect.objectContaining({ host: "sway.vote" })]),
            expect.arrayContaining([expect.objectContaining({ host: "app.sway.vote" })]),
        ]);
    });

    // @lat: [[mobile-expo-config#Deployment identifiers come from the environment#Links are claimed on both Sway hosts]]
    it("claims every link pattern on app.sway.vote as well as sway.vote", () => {
        const hostsOf = (filter: { data?: unknown }) => (filter.data as { host: string }[]).map((entry) => entry.host);
        const appHostFilter = build().android?.intentFilters?.find((filter) =>
            hostsOf(filter).includes("app.sway.vote"),
        );

        expect(appHostFilter?.autoVerify).toBe(true);
        expect(new Set(hostsOf(appHostFilter!))).toEqual(new Set(["app.sway.vote"]));
        expect(appHostFilter?.data).toHaveLength(DEEP_LINK_PATTERNS.length);
    });

    // @lat: [[mobile-sentry-init-design#Why the DSN is trimmed at config time]]
    it("strips whitespace from the Sentry DSN and leaves it absent when blank", () => {
        expect(build().extra?.sentryDsn).toBe("https://key@o1.ingest.us.sentry.io/1");

        process.env.SENTRY_DSN_MOBILE = " \n";

        expect(build().extra?.sentryDsn).toBeUndefined();
    });

    // @lat: [[mobile-expo-config#New Architecture is not a config key on Expo 55]]
    it("sets no newArchEnabled key", () => {
        expect(Object.keys(build())).not.toContain("newArchEnabled");
    });

    it("derives both platforms' deep links from one list", () => {
        const config = build();

        expect(config.ios?.associatedDomains).toHaveLength(5);
        config.android?.intentFilters?.forEach((filter) => {
            expect(filter.data).toHaveLength(DEEP_LINK_PATTERNS.length);
        });
    });
});
