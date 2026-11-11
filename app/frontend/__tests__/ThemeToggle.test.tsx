import { fireEvent, render, screen, cleanup } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// ── Module mocks ────────────────────────────────────────────────────────────

const routerPatch = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} })),
    router: {
        patch: (...args: unknown[]) => routerPatch(...args),
    },
}));

vi.mock("app/frontend/components/ui/tooltip", () => ({
    TooltipProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    TooltipTrigger: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    TooltipContent: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button {...props}>{children}</button>
    ),
}));

import { usePage } from "@inertiajs/react";
import ThemeToggle from "app/frontend/components/drawer/ThemeToggle";

function setUsePageProps(props: Record<string, unknown>) {
    vi.mocked(usePage).mockReturnValue({ props } as unknown as ReturnType<typeof usePage>);
}

// ── Tests ───────────────────────────────────────────────────────────────────

describe("ThemeToggle (server-rendered theme)", () => {
    beforeEach(() => {
        routerPatch.mockReset();
        vi.mocked(usePage).mockReset();
        setUsePageProps({});
        document.documentElement.classList.remove("dark");
        document.documentElement.removeAttribute("data-theme-mode");
    });

    afterEach(() => {
        cleanup();
    });

    // 3-way cycle ----------------------------------------------------------------

    it("cycles light -> system on click and announces next via aria-label", () => {
        setUsePageProps({ theme: { preference: "light", id: "cornerstore" } });
        render(<ThemeToggle />);

        const button = screen.getByRole("button");
        expect(button).toHaveAttribute("aria-label", "Theme: Light. Click for Auto.");
        expect(button).toHaveTextContent("Light");
        // A button that cycles through three states carries no aria-pressed.
        expect(button).not.toHaveAttribute("aria-pressed");

        fireEvent.click(button);

        // The click handler updates the page at once, without waiting for the
        // server to answer.
        expect(document.documentElement.dataset.themeMode).toBe("auto");
        expect(document.documentElement.classList.contains("dark")).toBe(false);
    });

    it("cycles system -> dark on click and adds .dark class for instant feedback", () => {
        setUsePageProps({ theme: { preference: "auto", id: "cornerstore" } });
        render(<ThemeToggle />);

        const button = screen.getByRole("button");
        expect(button).toHaveTextContent("Auto");
        fireEvent.click(button);

        expect(document.documentElement.dataset.themeMode).toBe("dark");
        expect(document.documentElement.classList.contains("dark")).toBe(true);
    });

    it("cycles dark -> light on click and removes the .dark class", () => {
        setUsePageProps({ theme: { preference: "dark", id: "cornerstore" } });
        render(<ThemeToggle />);

        const button = screen.getByRole("button");
        expect(button).toHaveTextContent("Dark");
        fireEvent.click(button);

        expect(document.documentElement.dataset.themeMode).toBe("light");
        expect(document.documentElement.classList.contains("dark")).toBe(false);
    });

    // Server-sync (cookie + DB) --------------------------------------------------

    it("PATCHes /users/preferences with normalized theme_mode (system -> auto)", () => {
        setUsePageProps({ theme: { preference: "light", id: "cornerstore" } });
        render(<ThemeToggle />);

        // The click moves "light" to "system", and the PATCH must send "auto".
        fireEvent.click(screen.getByRole("button"));

        expect(routerPatch).toHaveBeenCalledTimes(1);
        const [path, body] = routerPatch.mock.calls[0];
        expect(path).toBe("/users/preferences");
        expect(body).toEqual({ preferences: { theme_mode: "auto" } });
    });

    it("passes through 'light' and 'dark' verbatim to the server", () => {
        setUsePageProps({ theme: { preference: "auto", id: "cornerstore" } });
        render(<ThemeToggle />);

        fireEvent.click(screen.getByRole("button"));

        expect(routerPatch).toHaveBeenCalledTimes(1);
        expect(routerPatch.mock.calls[0][1]).toEqual({ preferences: { theme_mode: "dark" } });
    });

    it("PATCHes for anonymous visitors too (controller writes signed cookie)", () => {
        // A visitor who is not signed in keeps their choice in a signed cookie.
        // The hook always sends the PATCH; the controller decides whether to
        // also write users.theme_mode.
        setUsePageProps({ theme: { preference: "light", id: "cornerstore" } });
        render(<ThemeToggle />);

        fireEvent.click(screen.getByRole("button"));

        expect(routerPatch).toHaveBeenCalledTimes(1);
    });

    // Starting value (the preference the server rendered) ------------------------

    it("seeds preference from inertia shared prop theme.preference='auto' as 'Auto'", () => {
        setUsePageProps({ theme: { preference: "auto", id: "cornerstore" } });
        render(<ThemeToggle />);

        expect(screen.getByRole("button")).toHaveTextContent("Auto");
    });

    it("falls back to 'Light' when no shared prop is present", () => {
        setUsePageProps({});
        render(<ThemeToggle />);

        expect(screen.getByRole("button")).toHaveTextContent("Light");
    });

    it("seeds preference from server 'dark' verbatim", () => {
        setUsePageProps({ theme: { preference: "dark", id: "cornerstore" } });
        render(<ThemeToggle />);

        expect(screen.getByRole("button")).toHaveTextContent("Dark");
    });
});
