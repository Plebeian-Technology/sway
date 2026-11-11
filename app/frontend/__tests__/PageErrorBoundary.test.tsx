// The page-level error boundary catches a crash while a page renders, keeps the
// surrounding layout (nav, header, and the rest) alive, and clears itself when
// the user navigates somewhere else. AppErrorFallback, the app-wide fallback
// screen, must no longer pull in react-bootstrap.

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

const usePageMock = vi.fn<() => { url: string }>(() => ({ url: "/a" }));
vi.mock("@inertiajs/react", () => ({ usePage: () => usePageMock() }));
// Swap in a fake for the shared error handler, so these tests do not report to
// Sentry or wipe browser storage. That handler is unchanged and tested
// elsewhere.
vi.mock("app/frontend/components/error_handling/utils", () => ({ onRenderError: vi.fn<(error: Error) => void>() }));

import PageErrorBoundary from "app/frontend/components/error_handling/PageErrorBoundary";
import { onRenderError } from "app/frontend/components/error_handling/utils";
import appErrorFallbackSource from "app/frontend/components/error_handling/AppErrorFallback.tsx?raw";

afterEach(() => {
    cleanup();
    usePageMock.mockReset();
    usePageMock.mockReturnValue({ url: "/a" });
    vi.mocked(onRenderError).mockClear();
});

describe("PageErrorBoundary", () => {
    it("renders the fallback on a child error while content outside the boundary survives", () => {
        const Boom = () => {
            throw new Error("boom");
        };
        render(
            <div>
                <span>chrome-sibling</span>
                <PageErrorBoundary>
                    <Boom />
                </PageErrorBoundary>
            </div>,
        );

        expect(screen.getByRole("alert")).toBeTruthy();
        // The element next to the boundary is still there: the whole app did not go down.
        expect(screen.getByText("chrome-sibling")).toBeTruthy();
    });

    it("re-attempts children when the URL changes (reset on navigation)", () => {
        let shouldThrow = true;
        const Maybe = () => {
            if (shouldThrow) throw new Error("boom");
            return <div>healthy page</div>;
        };

        usePageMock.mockReturnValue({ url: "/a" });
        const { rerender } = render(
            <PageErrorBoundary>
                <Maybe />
            </PageErrorBoundary>,
        );
        expect(screen.getByRole("alert")).toBeTruthy();

        // Navigating changes the URL, so the boundary starts over and mounts
        // its child again — and this time the child renders fine.
        shouldThrow = false;
        usePageMock.mockReturnValue({ url: "/b" });
        rerender(
            <PageErrorBoundary>
                <Maybe />
            </PageErrorBoundary>,
        );
        expect(screen.getByText("healthy page")).toBeTruthy();
    });

    it("preserves healthy children's local state across a URL change (no key remount)", () => {
        const Counter = () => {
            const [n, setN] = React.useState(0);
            return (
                <button type="button" onClick={() => setN(n + 1)}>
                    count:{n}
                </button>
            );
        };

        usePageMock.mockReturnValue({ url: "/a" });
        const { rerender } = render(
            <PageErrorBoundary>
                <Counter />
            </PageErrorBoundary>,
        );
        fireEvent.click(screen.getByRole("button"));
        expect(screen.getByRole("button").textContent).toBe("count:1");

        // Navigate. Rebuilding the children on every URL change would knock the
        // counter back to 0 — the bug that used to wipe the paste-summary
        // dialog. resetKey has to leave the count alone.
        usePageMock.mockReturnValue({ url: "/b" });
        rerender(
            <PageErrorBoundary>
                <Counter />
            </PageErrorBoundary>,
        );
        expect(screen.getByRole("button").textContent).toBe("count:1");
    });

    it("AppErrorFallback no longer imports react-bootstrap", () => {
        // Match the import statement itself, not a passing mention in a comment.
        expect(appErrorFallbackSource).not.toMatch(/from\s+["']react-bootstrap["']/);
    });
});

// @lat: [[error-boundary-captures#One capture per error, however the reader arrives at it]]
describe("PageErrorBoundary — how many times an error is reported", () => {
    const Thrower = ({ message }: { message: string }) => {
        throw new Error(message);
    };

    it("reports once when a healthy page is followed by a throwing one", () => {
        usePageMock.mockReturnValue({ url: "/a" });
        const { rerender } = render(
            <PageErrorBoundary>
                <div>healthy page</div>
            </PageErrorBoundary>,
        );
        expect(screen.getByText("healthy page")).toBeTruthy();

        usePageMock.mockReturnValue({ url: "/b" });
        rerender(
            <PageErrorBoundary>
                <Thrower message="boom-b" />
            </PageErrorBoundary>,
        );

        expect(screen.getByRole("alert")).toBeTruthy();
        expect(vi.mocked(onRenderError)).toHaveBeenCalledTimes(1);
    });

    it("reports each distinct error once when a throwing page is followed by another", () => {
        usePageMock.mockReturnValue({ url: "/a" });
        const { rerender } = render(
            <PageErrorBoundary>
                <Thrower message="boom-a" />
            </PageErrorBoundary>,
        );
        expect(vi.mocked(onRenderError)).toHaveBeenCalledTimes(1);

        usePageMock.mockReturnValue({ url: "/b" });
        rerender(
            <PageErrorBoundary>
                <Thrower message="boom-b" />
            </PageErrorBoundary>,
        );

        expect(screen.getByRole("alert")).toBeTruthy();
        expect(vi.mocked(onRenderError)).toHaveBeenCalledTimes(2);
        expect(vi.mocked(onRenderError).mock.calls.map(([error]) => (error as Error).message)).toEqual([
            "boom-a",
            "boom-b",
        ]);
    });
});
