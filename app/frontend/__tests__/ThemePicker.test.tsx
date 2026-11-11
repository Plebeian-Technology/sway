import { fireEvent, render, screen, cleanup } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// ── Module mocks ────────────────────────────────────────────────────────────

const routerPatch = vi.fn<(url: string, data?: unknown, config?: unknown) => void>();

vi.mock("@inertiajs/react", () => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} })),
    router: {
        patch: (url: string, data?: unknown, config?: unknown) => routerPatch(url, data, config),
    },
}));

// The Radix Select does not work in jsdom, the fake browser these tests run in:
// it needs pointer capture, scrollIntoView, and portals. Swap it for a plain
// <select>, so what actually gets tested is how ThemePicker hooks up value and
// onValueChange.
vi.mock("app/frontend/components/ui/select", () => ({
    Select: ({
        value,
        onValueChange,
        children,
    }: {
        value: string;
        onValueChange: (v: string) => void;
        children: React.ReactNode;
    }) => (
        <select value={value} onChange={(e) => onValueChange(e.target.value)}>
            {children}
        </select>
    ),
    SelectTrigger: () => null,
    SelectValue: () => null,
    SelectContent: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    SelectItem: ({ value, children }: { value: string; children: React.ReactNode }) => (
        <option value={value}>{children}</option>
    ),
}));

import { usePage } from "@inertiajs/react";
import ThemePicker from "app/frontend/components/drawer/ThemePicker";

function setUsePageProps(props: Record<string, unknown>) {
    vi.mocked(usePage).mockReturnValue({ props } as unknown as ReturnType<typeof usePage>);
}

// ── Tests ───────────────────────────────────────────────────────────────────

describe("ThemePicker (theme select)", () => {
    beforeEach(() => {
        routerPatch.mockReset();
        vi.mocked(usePage).mockReset();
        setUsePageProps({});
        document.documentElement.removeAttribute("data-theme");
    });

    afterEach(() => {
        cleanup();
    });

    it("renders an option per selectable (non-hidden) theme", () => {
        setUsePageProps({ theme: { preference: "light", id: "sway" } });
        render(<ThemePicker />);

        expect(screen.getByRole("option", { name: "Sway" })).toBeInTheDocument();
        expect(screen.getByRole("option", { name: "Ballot" })).toBeInTheDocument();
        expect(screen.getByRole("option", { name: "Corner Store" })).toBeInTheDocument();
        expect(screen.getByRole("option", { name: "Monochrome" })).toBeInTheDocument();
        expect(screen.getByRole("option", { name: "Service Manual" })).toBeInTheDocument();
        expect(screen.getByRole("option", { name: "Swiss Notice" })).toBeInTheDocument();
        // Banner is registered but hidden, so it is not offered as a choice.
        expect(screen.queryByRole("option", { name: "Banner" })).not.toBeInTheDocument();
    });

    it("still shows a hidden theme as an option when it is the active theme", () => {
        setUsePageProps({ theme: { preference: "light", id: "banner" } });
        render(<ThemePicker />);

        // Someone already on the hidden Banner theme can see it and switch away.
        expect(screen.getByRole("option", { name: "Banner" })).toBeInTheDocument();
        expect(screen.getByRole("combobox")).toHaveValue("banner");
    });

    it("reflects the active theme from the inertia shared prop", () => {
        setUsePageProps({ theme: { preference: "light", id: "ballot" } });
        render(<ThemePicker />);

        expect(screen.getByRole("combobox")).toHaveValue("ballot");
    });

    it("defaults the active theme to sway when no shared prop is present", () => {
        setUsePageProps({});
        render(<ThemePicker />);

        expect(screen.getByRole("combobox")).toHaveValue("sway");
    });

    it("optimistically writes data-theme and PATCHes /users/preferences on change", () => {
        setUsePageProps({ theme: { preference: "light", id: "sway" } });
        render(<ThemePicker />);

        fireEvent.change(screen.getByRole("combobox"), { target: { value: "ballot" } });

        // The change handler updates the page at once, without waiting for the
        // server to answer.
        expect(document.documentElement.dataset.theme).toBe("ballot");

        expect(routerPatch).toHaveBeenCalledTimes(1);
        const [path, body] = routerPatch.mock.calls[0];
        expect(path).toBe("/users/preferences");
        expect(body).toEqual({ preferences: { theme_id: "ballot" } });
    });
});
