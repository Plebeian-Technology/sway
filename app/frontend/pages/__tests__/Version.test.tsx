// @lat: [[system-shape#System shape#Deployment#The version page has three answers, not two]]

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

const release: { current: Partial<sway.IRelease> | null } = { current: null };

vi.mock("@inertiajs/react", () => ({
    Head: () => null,
    Link: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    usePage: () => ({ props: { release: release.current } }),
}));

import Version from "app/frontend/pages/Version";

describe("Version", () => {
    afterEach(() => {
        cleanup();
        release.current = null;
    });

    it("says the build is the commit when the deploy recorded a clean tree", () => {
        release.current = { sha: "abc123", built_from_committed_tree: true, uncommitted_digest: null };

        render(<Version />);

        expect(screen.getByText("exactly the commit above")).toBeTruthy();
    });

    it("names the extra changes when the deploy recorded a dirty tree", () => {
        release.current = { sha: "abc123", built_from_committed_tree: false, uncommitted_digest: "a1b2c3d4" };

        render(<Version />);

        expect(screen.getByText(/uncommitted changes \(a1b2c3d4\)/)).toBeTruthy();
        expect(screen.queryByText("exactly the commit above")).toBeNull();
    });

    it("says it does not know when no deploy recorded an answer", () => {
        release.current = { sha: "abc123", built_from_committed_tree: null, uncommitted_digest: null };

        render(<Version />);

        expect(screen.getByText(/not recorded/)).toBeTruthy();
        expect(screen.queryByText("exactly the commit above")).toBeNull();
    });
});
