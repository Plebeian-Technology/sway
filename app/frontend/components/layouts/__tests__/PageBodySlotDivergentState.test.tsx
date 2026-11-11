// qualifiesForDim delegates to qualifiesForPlaceholder today, so the store can never
// produce dim-without-placeholder through a real event. PageBodySlot's contract admits
// it, and these pin that contract so the branches are not untested.
// @lat: [[system-shape#What a reader sees during the round trip#Why the outgoing page is not painted under the placeholder]]

import { render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import type { INavigationState } from "app/frontend/navigation/navigationStore";

const navigationState = vi.hoisted(() => ({
    current: { placeholder: null, pageName: null, dim: false } as INavigationState,
}));

vi.mock("app/frontend/navigation/navigationStore", async (importActual) => ({
    ...(await importActual<typeof import("app/frontend/navigation/navigationStore")>()),
    useNavigationState: () => navigationState.current,
}));

const { default: PageBodySlot } = await import("app/frontend/components/layouts/PageBodySlot");

const renderWithState = (state: INavigationState) => {
    navigationState.current = state;
    return render(
        <PageBodySlot>
            <div data-testid="page-content">Page content</div>
        </PageBodySlot>,
    );
};

describe("PageBodySlot with dim raised and no placeholder", () => {
    it("dims and marks the region inert without rendering a placeholder", () => {
        renderWithState({ placeholder: null, pageName: null, dim: true });

        const outgoing = screen.getByTestId("page-body-outgoing");
        expect(outgoing).toHaveAttribute("inert");
        expect(outgoing.className).toContain("nav-leaving");
        expect(outgoing.className).not.toContain("nav-replaced");
        expect(screen.queryByTestId("page-body-placeholder")).not.toBeInTheDocument();
    });

    it("still reports busy, and falls back to 'page' when no page name came with the dim", () => {
        renderWithState({ placeholder: null, pageName: null, dim: true });

        const slot = screen.getByTestId("page-body-slot");
        expect(slot).toHaveAttribute("aria-busy", "true");
        expect(within(slot).getByRole("status")).toHaveTextContent("Loading page");
    });

    it("announces the page name when one came with the dim", () => {
        renderWithState({ placeholder: null, pageName: "Past Bills", dim: true });

        const slot = screen.getByTestId("page-body-slot");
        expect(within(slot).getByRole("status")).toHaveTextContent("Loading Past Bills");
    });

    it("keeps the region interactive and silent at idle", () => {
        renderWithState({ placeholder: null, pageName: null, dim: false });

        const slot = screen.getByTestId("page-body-slot");
        expect(slot).not.toHaveAttribute("aria-busy");
        expect(screen.getByTestId("page-body-outgoing")).not.toHaveAttribute("inert");
        expect(within(slot).getByRole("status")).toHaveTextContent("");
    });
});
