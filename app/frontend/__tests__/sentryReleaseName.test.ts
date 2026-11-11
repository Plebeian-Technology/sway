import { describe, expect, it } from "vitest";
import { sentryReleaseName } from "../../../vite/sentryReleaseName";

// @lat: [[sentry-release-name-dockerfile-duplication#Why sentryReleaseName.test.ts cares most about the no-value case]]

describe("sentryReleaseName", () => {
    it("uses the commit the deploy was built from", () => {
        expect(sentryReleaseName({ SWAY_RELEASE_SHA: "017a7a232f1e4c0b8a9d" })).toBe("017a7a232f1e4c0b8a9d");
    });

    it("gives no name when the build was not told the commit", () => {
        expect(sentryReleaseName({})).toBeUndefined();
    });

    it("gives no name for an empty setting", () => {
        expect(sentryReleaseName({ SWAY_RELEASE_SHA: "" })).toBeUndefined();
    });

    // config/deploy.yml fills this in from a shell command. A command that
    // prints nothing still leaves a newline behind.
    it("gives no name for a setting that holds only blank space", () => {
        expect(sentryReleaseName({ SWAY_RELEASE_SHA: "  \n" })).toBeUndefined();
    });

    it("drops the newline a shell command leaves on the end", () => {
        expect(sentryReleaseName({ SWAY_RELEASE_SHA: "017a7a232\n" })).toBe("017a7a232");
    });
});
