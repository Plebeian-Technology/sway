import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

const { captureReferralAttributionMock, trackFunnelStepOnceMock } = vi.hoisted(() => ({
    captureReferralAttributionMock: vi.fn<() => void>(),
    trackFunnelStepOnceMock: vi.fn<(step: string) => void>(),
}));

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href }: { children?: React.ReactNode; href?: string }) => <a href={href}>{children}</a>,
    usePage: () => ({ props: {} }),
}));

vi.mock("app/frontend/sway_utils/funnelTracker", () => ({
    captureReferralAttribution: captureReferralAttributionMock,
    trackFunnelStepOnce: trackFunnelStepOnceMock,
}));

vi.mock("app/frontend/components/auth/PasskeyPanel", () => ({
    default: () => <div data-testid="passkey-panel" />,
}));
vi.mock("app/frontend/components/auth/HomeHero", () => ({
    default: () => <div data-testid="home-hero" />,
}));

import { homeLayoutFor } from "app/frontend/components/home/layouts/index";
import { THEMES, type ThemeId } from "app/frontend/styles/themes";

const ALL_THEMES: ThemeId[] = THEMES.map((t) => t.id);

// @lat: [[home-layout-theme-concepts#Themed home layout design concepts]]
describe.each(ALL_THEMES)("home layout for the %s theme", (themeId) => {
    afterEach(() => {
        cleanup();
        captureReferralAttributionMock.mockReset();
        trackFunnelStepOnceMock.mockReset();
    });

    it("mounts without throwing", () => {
        const Layout = homeLayoutFor(themeId);
        render(<Layout />);

        expect(document.body.textContent?.trim()).not.toBe("");
    });

    it("puts the sign-in panel on the page", () => {
        const Layout = homeLayoutFor(themeId);
        render(<Layout />);

        const hasEntryPoint =
            screen.queryByTestId("passkey-panel") !== null || screen.queryByTestId("home-hero") !== null;
        expect(hasEntryPoint).toBe(true);
    });
});

describe.each(["sway", "monochrome", "service-manual", "swiss-grid"] as const)(
    "home landing funnel tracking for %s",
    (themeId) => {
        afterEach(() => {
            cleanup();
            captureReferralAttributionMock.mockReset();
            trackFunnelStepOnceMock.mockReset();
        });

        it("records referral attribution and the landing funnel step on mount", () => {
            const Layout = homeLayoutFor(themeId);
            render(<Layout />);

            expect(captureReferralAttributionMock).toHaveBeenCalledTimes(1);
            expect(trackFunnelStepOnceMock).toHaveBeenCalledWith("landing");
        });
    },
);
