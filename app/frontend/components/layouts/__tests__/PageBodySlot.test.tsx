import type { PendingVisit } from "@inertiajs/core";
import { act, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import PageBodySlot from "app/frontend/components/layouts/PageBodySlot";
import { pendingVisitFixture } from "app/frontend/navigation/__tests__/pendingVisitFixture";

const buildVisit = (overrides: Partial<PendingVisit> = {}): PendingVisit =>
    pendingVisitFixture({ id: "visit-1", url: new URL("/bills", window.location.href), ...overrides });

const dispatchInertia = (name: string, detail: Record<string, unknown> = {}): void => {
    act(() => {
        document.dispatchEvent(new CustomEvent(`inertia:${name}`, { cancelable: true, detail }));
    });
};

// An attributed clear: the unattributed events only shorten the treatment's bound.
const clearNavigationState = (): void => {
    dispatchInertia("before", { visit: buildVisit({ id: "reset-visit" }) });
    dispatchInertia("success", { page: {}, visitId: "reset-visit" });
};

const TestTree = () => (
    <div>
        <div data-testid="sibling">Sibling content</div>
        <PageBodySlot>
            <div data-testid="page-content">Page content</div>
        </PageBodySlot>
    </div>
);

afterEach(() => {
    clearNavigationState();
});

describe("PageBodySlot — one qualifying navigation, end to end", () => {
    it("shows the destination's placeholder and marks the outgoing region inert on a qualifying visit", () => {
        render(<TestTree />);
        dispatchInertia("before", { visit: buildVisit() });

        const outgoing = screen.getByTestId("page-body-outgoing");
        expect(outgoing).toHaveAttribute("inert");
        expect(screen.getByTestId("page-body-placeholder")).toBeInTheDocument();
        expect(screen.getByTestId("page-body-slot")).toHaveAttribute("aria-busy", "true");
    });

    it("stops painting the outgoing page while the placeholder holds the cell, rather than dimming it behind the skeleton", () => {
        render(<TestTree />);
        dispatchInertia("before", { visit: buildVisit() });

        const outgoing = screen.getByTestId("page-body-outgoing");
        expect(outgoing.className).toContain("nav-replaced");
        expect(outgoing.className).not.toContain("nav-leaving");
    });

    it("restores the outgoing page's paint once the treatment clears", () => {
        render(<TestTree />);
        dispatchInertia("before", { visit: buildVisit() });
        dispatchInertia("success", { page: {}, visitId: "visit-1" });

        const outgoing = screen.getByTestId("page-body-outgoing");
        expect(outgoing.className).not.toContain("nav-replaced");
        expect(outgoing.className).not.toContain("nav-leaving");
    });

    it("keeps the outgoing page in the layout while it is unpainted, so the swap moves nothing", () => {
        render(<TestTree />);
        dispatchInertia("before", { visit: buildVisit() });

        const outgoing = screen.getByTestId("page-body-outgoing");
        expect(outgoing).toBeInTheDocument();
        expect(outgoing.className).not.toContain("hidden");
        expect(within(outgoing).getByTestId("page-content")).toBeInTheDocument();
    });

    const clearingEvents: Array<{ name: string; detail: Record<string, unknown> }> = [
        { name: "finish", detail: { visit: buildVisit() } },
        { name: "success", detail: { page: {}, visitId: "visit-1" } },
        { name: "error", detail: { errors: {}, visitId: "visit-1" } },
    ];

    it.each(clearingEvents)(
        "clears the placeholder, dim and busy state on an attributed $name (the prefetch-consuming path fires no start and no finish)",
        ({ name, detail }) => {
            render(<TestTree />);
            dispatchInertia("before", { visit: buildVisit() });
            dispatchInertia(name, detail);

            expect(screen.queryByTestId("page-body-placeholder")).not.toBeInTheDocument();
            expect(screen.getByTestId("page-body-outgoing")).not.toHaveAttribute("inert");
            expect(screen.getByTestId("page-body-slot")).not.toHaveAttribute("aria-busy");
        },
    );

    it.each(["networkError", "httpException"])(
        "holds the placeholder, dim and busy state through an unattributed %s, which may belong to a background poll",
        (name) => {
            render(<TestTree />);
            dispatchInertia("before", { visit: buildVisit() });
            dispatchInertia(name, { error: new Error("offline"), response: { status: 500 } });

            expect(screen.getByTestId("page-body-placeholder")).toBeInTheDocument();
            expect(screen.getByTestId("page-body-outgoing")).toHaveAttribute("inert");
            expect(screen.getByTestId("page-body-slot")).toHaveAttribute("aria-busy", "true");
        },
    );

    it("leaves the DOM byte-identical to idle for a partial reload", () => {
        render(<TestTree />);
        const idleHtml = screen.getByTestId("page-body-slot").outerHTML;

        dispatchInertia("before", {
            visit: buildVisit({ only: ["bills"], async: true, preserveState: true }),
        });

        expect(screen.getByTestId("page-body-slot").outerHTML).toBe(idleHtml);
    });

    it("renders exactly one status live region, announcing during a qualifying visit and empty when idle", () => {
        render(<TestTree />);
        const slot = screen.getByTestId("page-body-slot");

        expect(within(slot).getAllByRole("status")).toHaveLength(1);
        expect(within(slot).getByRole("status")).toHaveTextContent("");

        dispatchInertia("before", { visit: buildVisit() });

        expect(within(slot).getAllByRole("status")).toHaveLength(1);
        expect(within(slot).getByRole("status")).toHaveTextContent("Loading All Bills");
    });

    it("moves focus to the status region when inert blurs the link the reader activated", () => {
        render(
            <div>
                <div data-testid="sibling">Sibling content</div>
                <PageBodySlot>
                    <a href="/bills/1" data-testid="bill-row">
                        A bill
                    </a>
                </PageBodySlot>
            </div>,
        );

        const row = screen.getByTestId("bill-row");
        act(() => row.focus());
        expect(document.activeElement).toBe(row);

        dispatchInertia("before", { visit: buildVisit() });

        const slot = screen.getByTestId("page-body-slot");
        expect(document.activeElement).not.toBe(document.body);
        expect(document.activeElement).toBe(within(slot).getByRole("status"));
    });

    it("renders the status region ahead of the page body, so a Tab out of it enters the page", () => {
        render(<TestTree />);

        const slot = screen.getByTestId("page-body-slot");
        const status = within(slot).getByRole("status");
        const outgoing = screen.getByTestId("page-body-outgoing");

        expect(status.compareDocumentPosition(outgoing) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    });

    it("hands focus back to the page body when the treatment clears, rather than parking it on the status region", () => {
        render(
            <div>
                <PageBodySlot>
                    <a href="/bills/1" data-testid="bill-row">
                        A bill
                    </a>
                </PageBodySlot>
            </div>,
        );

        const slot = screen.getByTestId("page-body-slot");
        act(() => screen.getByTestId("bill-row").focus());
        dispatchInertia("before", { visit: buildVisit() });
        expect(document.activeElement).toBe(within(slot).getByRole("status"));

        dispatchInertia("success", { page: {}, visitId: "visit-1" });

        expect(document.activeElement).not.toBe(within(slot).getByRole("status"));
        expect(document.activeElement).toBe(screen.getByTestId("page-body-outgoing"));
    });

    it("leaves focus where the reader put it when the treatment clears and focus is no longer on the status region", () => {
        render(
            <div>
                <a href="/legislators" data-testid="drawer-link">
                    Representatives
                </a>
                <PageBodySlot>
                    <a href="/bills/1" data-testid="bill-row">
                        A bill
                    </a>
                </PageBodySlot>
            </div>,
        );

        act(() => screen.getByTestId("bill-row").focus());
        dispatchInertia("before", { visit: buildVisit() });

        const drawerLink = screen.getByTestId("drawer-link");
        act(() => drawerLink.focus());
        dispatchInertia("success", { page: {}, visitId: "visit-1" });

        expect(document.activeElement).toBe(drawerLink);
    });

    it("leaves focus alone when the reader had not focused anything inside the region", () => {
        render(<TestTree />);
        expect(document.activeElement).toBe(document.body);

        dispatchInertia("before", { visit: buildVisit() });

        expect(document.activeElement).toBe(document.body);
    });

    it("never steals focus from a control outside the region, such as a drawer link", () => {
        render(
            <div>
                <a href="/legislators" data-testid="drawer-link">
                    Representatives
                </a>
                <PageBodySlot>
                    <a href="/bills/1" data-testid="bill-row">
                        A bill
                    </a>
                </PageBodySlot>
            </div>,
        );

        const drawerLink = screen.getByTestId("drawer-link");
        act(() => screen.getByTestId("bill-row").focus());
        act(() => drawerLink.focus());

        dispatchInertia("before", { visit: buildVisit() });

        expect(document.activeElement).toBe(drawerLink);
    });

    it("does not read its own hand-back as a reader position, so a second navigation started from outside the region steals nothing", () => {
        render(
            <div>
                <a href="/legislators" data-testid="drawer-link">
                    Representatives
                </a>
                <PageBodySlot>
                    <a href="/bills/1" data-testid="bill-row">
                        A bill
                    </a>
                </PageBodySlot>
            </div>,
        );

        const slot = screen.getByTestId("page-body-slot");
        act(() => screen.getByTestId("bill-row").focus());
        dispatchInertia("before", { visit: buildVisit() });
        dispatchInertia("success", { page: {}, visitId: "visit-1" });
        expect(document.activeElement).toBe(screen.getByTestId("page-body-outgoing"));

        // Safari and Firefox do not focus an <a> on click, so the second navigation arrives
        // with focus on <body> and no focusin since the hand-back.
        act(() => (document.activeElement as HTMLElement).blur());
        expect(document.activeElement).toBe(document.body);

        dispatchInertia("before", {
            visit: buildVisit({ id: "visit-2", url: new URL("/legislators", window.location.href) }),
        });

        expect(document.activeElement).not.toBe(within(slot).getByRole("status"));
        expect(document.activeElement).toBe(document.body);
    });

    // @lat: [[system-shape#What a reader sees during the round trip#Why focus moves to the slot's status region]]
    it("moves focus to the status region when a navigation starts with focus still parked on the container", () => {
        render(
            <div>
                <a href="/legislators" data-testid="drawer-link">
                    Representatives
                </a>
                <PageBodySlot>
                    <a href="/bills/1" data-testid="bill-row">
                        A bill
                    </a>
                </PageBodySlot>
            </div>,
        );

        const slot = screen.getByTestId("page-body-slot");
        act(() => screen.getByTestId("bill-row").focus());
        dispatchInertia("before", { visit: buildVisit() });
        dispatchInertia("success", { page: {}, visitId: "visit-1" });
        expect(document.activeElement).toBe(screen.getByTestId("page-body-outgoing"));

        dispatchInertia("before", {
            visit: buildVisit({ id: "visit-2", url: new URL("/legislators", window.location.href) }),
        });

        expect(document.activeElement).not.toBe(document.body);
        expect(document.activeElement).toBe(within(slot).getByRole("status"));
    });

    it("never applies inert or the dim class to a sibling rendered outside PageBodySlot", () => {
        render(<TestTree />);
        dispatchInertia("before", { visit: buildVisit() });

        const sibling = screen.getByTestId("sibling");
        expect(sibling).not.toHaveAttribute("inert");
        expect(sibling.className).not.toContain("nav-leaving");
    });

    it("every placeholder block carries aria-hidden and the placeholder contains no other text nodes", () => {
        render(<TestTree />);
        dispatchInertia("before", { visit: buildVisit() });

        const placeholder = screen.getByTestId("page-body-placeholder");
        const blocks = placeholder.querySelectorAll("[aria-hidden='true']");
        expect(blocks.length).toBeGreaterThan(0);
        expect(placeholder.textContent).toBe("");
    });
});
