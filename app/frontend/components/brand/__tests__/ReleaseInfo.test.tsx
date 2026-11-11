// @lat: [[system-shape#Deployment#The logo tooltip includes the running build]]

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

const release: { current: Partial<sway.IRelease> | null } = { current: null };
const user: { current: { phone: string } | null } = { current: null };

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({ props: { release: release.current } }),
}));

vi.mock("app/frontend/hooks/users/useUser", () => ({
    useUser: () => user.current,
}));

// @lat: [[system-shape#Deployment#The logo tooltip includes the running build]]
vi.mock("app/frontend/components/ui/tooltip", () => ({
    Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    TooltipProvider: ({ children }: { children: React.ReactNode; delayDuration?: number }) => <>{children}</>,
    TooltipTrigger: ({ children }: { children: React.ReactNode; asChild?: boolean }) => <>{children}</>,
    TooltipContent: ({ children }: { children: React.ReactNode }) => <span data-testid="tooltip">{children}</span>,
}));

import ReleaseInfo from "app/frontend/components/brand/ReleaseInfo";

describe("ReleaseInfo", () => {
    afterEach(() => {
        cleanup();
        release.current = null;
        user.current = null;
    });

    it("says the build is the commit when the deploy recorded a clean tree", () => {
        release.current = { short_sha: "abc12345", built_from_committed_tree: true, uncommitted_digest: null };

        render(<ReleaseInfo>logo</ReleaseInfo>);

        expect(screen.getByText("exactly that commit")).toBeTruthy();
    });

    it("shows the signed-in user in development and omits the row for a guest", () => {
        user.current = { phone: "4105551234" };

        const { rerender } = render(<ReleaseInfo>logo</ReleaseInfo>);

        expect(screen.getByText("(410) 555 - 1234")).toBeTruthy();

        user.current = null;
        rerender(<ReleaseInfo>logo</ReleaseInfo>);

        expect(screen.queryByText("User")).toBeNull();
    });

    it("names the extra changes when the deploy recorded a dirty tree", () => {
        release.current = { short_sha: "abc12345", built_from_committed_tree: false, uncommitted_digest: "a1b2c3d4" };

        render(<ReleaseInfo>logo</ReleaseInfo>);

        expect(screen.getByText(/uncommitted changes \(a1b2c3d4\)/)).toBeTruthy();
        expect(screen.queryByText("exactly that commit")).toBeNull();
    });

    it("says it does not know when no deploy recorded an answer", () => {
        release.current = { short_sha: "abc12345", built_from_committed_tree: null, uncommitted_digest: null };

        render(<ReleaseInfo>logo</ReleaseInfo>);

        expect(screen.getByText("not recorded")).toBeTruthy();
        expect(screen.queryByText("exactly that commit")).toBeNull();
    });
});
