/**
 // @lat: [[sway-error-scrubber-design#Why the mobile breadcrumb hook drops push-token entries]]
 */

import { scrubPushTokenBreadcrumb } from "../../src/observability/sentry";

describe("scrubPushTokenBreadcrumb", () => {
    test("drops a breadcrumb whose data references getDevicePushTokenAsync", () => {
        const bc = {
            category: "console",
            message: "called getDevicePushTokenAsync",
            data: { method: "getDevicePushTokenAsync" },
        };
        expect(scrubPushTokenBreadcrumb(bc)).toBeNull();
    });

    test("drops a breadcrumb whose URL matches /api/v1/devices/push_token", () => {
        const bc = {
            category: "fetch",
            data: { url: "https://app.sway.vote/api/v1/devices/push_token", method: "PATCH" },
        };
        expect(scrubPushTokenBreadcrumb(bc)).toBeNull();
    });

    test("drops a breadcrumb whose URL matches /api/v1/devices (registration)", () => {
        const bc = { category: "fetch", data: { url: "https://app.sway.vote/api/v1/devices/42" } };
        expect(scrubPushTokenBreadcrumb(bc)).toBeNull();
    });

    test("passes through unrelated breadcrumbs unchanged", () => {
        const bc = { category: "navigation", data: { from: "Home", to: "Bills" } };
        expect(scrubPushTokenBreadcrumb(bc)).toBe(bc);
    });
});
