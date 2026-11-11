import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const routerDeleteMock = vi.fn<(url: string, options?: unknown) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        delete: (url: string, options?: unknown) => routerDeleteMock(url, options),
    },
}));

vi.mock("app/frontend/components/SwayLogo", () => ({
    default: () => <div data-testid="sway-logo" />,
}));

import AppErrorFallback from "app/frontend/components/error_handling/AppErrorFallback";

afterEach(() => {
    cleanup();
    routerDeleteMock.mockClear();
    localStorage.clear();
    sessionStorage.clear();
});

describe("AppErrorFallback", () => {
    it("clears localStorage and sessionStorage before calling router.delete on Log Out", () => {
        localStorage.setItem("sway_draft", "sensitive");
        sessionStorage.setItem("sway_tab", "current");

        render(<AppErrorFallback />);

        fireEvent.click(screen.getByRole("button", { name: /Log Out/i }));

        expect(localStorage.length).toBe(0);
        expect(sessionStorage.length).toBe(0);
        expect(routerDeleteMock).toHaveBeenCalledWith(
            "/users/webauthn/sessions/0",
            expect.objectContaining({
                onFinish: expect.any(Function),
            }),
        );
    });
});
