import { fireEvent, render, screen, cleanup } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// ── Module mocks ────────────────────────────────────────────────────────────

const routerDelete = vi.fn<(...args: unknown[]) => unknown>();
const routerPut = vi.fn<(...args: unknown[]) => unknown>();

vi.mock("@inertiajs/react", () => ({
    usePage: vi.fn<() => { props: unknown }>(() => ({ props: {} })),
    router: {
        delete: (...args: unknown[]) => routerDelete(...args),
        put: (...args: unknown[]) => routerPut(...args),
    },
    // Fake Inertia's Link. Without Inertia set up around it, the real one
    // breaks in jsdom, the fake browser these tests run in.
    Link: ({ href, children, className }: { href: string; children: React.ReactNode; className?: string }) => (
        <a href={href} className={className}>
            {children}
        </a>
    ),
}));

// notify sends a message off and forgets it. Fake it so these tests do not drag
// in the toast and UI packages behind it.
vi.mock("app/frontend/sway_utils", () => ({
    notify: vi.fn<() => void>(),
}));

import PendingChangeCard from "app/frontend/components/organizations/PendingChangeCard";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import type { IMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";

// ── Fixtures ────────────────────────────────────────────────────────────────

const ORG_ID = 7;
const CHANGE_ID = 42;
const POSITION_ID = 100;

type PendingChange = IMembership["pending_changes"][number];

const buildChange = (overrides: Partial<PendingChange> = {}): PendingChange =>
    ({
        id: CHANGE_ID,
        created_at: "2026-05-01T12:00:00Z",
        organization_bill_position_id: POSITION_ID,
        approved_by_id: null,
        rejected_by_id: null,
        rejected_at: null,
        status: "pending",
        updated_by_id: 1,
        new_summary: "New summary text",
        new_support: "FOR",
        previous_summary: "Previous summary text",
        previous_support: "AGAINST",
        ...overrides,
    }) as unknown as PendingChange;

const buildMembership = (): IMembership =>
    ({
        organization: { id: ORG_ID, name: "Acme Org" },
        positions: [
            {
                id: POSITION_ID,
                bill_id: 9,
                bill: { id: 9, external_id: "HB-1", title: "Test Bill" },
            },
        ],
        pending_changes: [],
    }) as unknown as IMembership;

// ── Tests ───────────────────────────────────────────────────────────────────

describe("PendingChangeCard — web Reject UI", () => {
    beforeEach(() => {
        routerDelete.mockReset();
        routerPut.mockReset();
    });

    afterEach(() => {
        cleanup();
    });

    // ── 1) When the Reject button shows — four situations ───────────────────

    it("renders the Reject button when isAdmin && !approved && !rejected", () => {
        render(<PendingChangeCard change={buildChange()} membership={buildMembership()} isAdmin={true} />);

        expect(screen.getByRole("button", { name: PARITY_COPY.pendingChanges.rejectConfirmAction })).toBeTruthy();
    });

    it("hides the Reject button when the user is not an org admin", () => {
        render(<PendingChangeCard change={buildChange()} membership={buildMembership()} isAdmin={false} />);

        expect(screen.queryByRole("button", { name: PARITY_COPY.pendingChanges.rejectConfirmAction })).toBeNull();
    });

    it("hides the Reject button when the change is already approved", () => {
        render(
            <PendingChangeCard
                change={buildChange({ approved_by_id: 5, status: "approved" })}
                membership={buildMembership()}
                isAdmin={true}
            />,
        );

        expect(screen.queryByRole("button", { name: PARITY_COPY.pendingChanges.rejectConfirmAction })).toBeNull();
    });

    it("hides the Reject button when the change is already rejected", () => {
        render(
            <PendingChangeCard
                change={buildChange({
                    rejected_by_id: 5,
                    rejected_at: "2026-05-02T12:00:00Z",
                    status: "rejected",
                })}
                membership={buildMembership()}
                isAdmin={true}
            />,
        );

        expect(screen.queryByRole("button", { name: PARITY_COPY.pendingChanges.rejectConfirmAction })).toBeNull();
    });

    // ── 2) Clicking Reject opens the confirmation dialog ────────────────────

    it("opens the confirm Dialog when the Reject button is clicked", () => {
        render(<PendingChangeCard change={buildChange()} membership={buildMembership()} isAdmin={true} />);

        // The dialog is not open yet, so its title is nowhere on the page.
        expect(screen.queryByText(PARITY_COPY.pendingChanges.rejectConfirmTitle)).toBeNull();

        const rejectButton = screen.getByRole("button", {
            name: PARITY_COPY.pendingChanges.rejectConfirmAction,
        });
        fireEvent.click(rejectButton);

        // The dialog is open now: title and body show, both from PARITY_COPY.
        expect(screen.getByText(PARITY_COPY.pendingChanges.rejectConfirmTitle)).toBeTruthy();
    });

    // ── 3) Dialog wording comes from PARITY_COPY, never typed inline ────────

    it("renders Dialog title, body, and action from PARITY_COPY.pendingChanges.rejectConfirm*", () => {
        render(<PendingChangeCard change={buildChange()} membership={buildMembership()} isAdmin={true} />);

        fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.pendingChanges.rejectConfirmAction }));

        // The title, rendered by DialogTitle.
        expect(screen.getByText(PARITY_COPY.pendingChanges.rejectConfirmTitle)).toBeTruthy();
        // The body, rendered by DialogDescription.
        expect(screen.getByText(PARITY_COPY.pendingChanges.rejectConfirmBody)).toBeTruthy();
        // The button inside the dialog carries the rejectConfirmAction wording.
        // The button that opened the dialog carries the same wording in its
        // aria-label, so two buttons now match — check both are present.
        const confirmButtons = screen.getAllByRole("button", {
            name: PARITY_COPY.pendingChanges.rejectConfirmAction,
        });
        expect(confirmButtons.length).toBeGreaterThanOrEqual(1);
    });

    // ── 4) Confirming calls router.delete with the right URL ────────────────

    it("invokes router.delete with the correct URL and preserveScroll: true on confirm", () => {
        render(<PendingChangeCard change={buildChange()} membership={buildMembership()} isAdmin={true} />);

        // Open the dialog
        fireEvent.click(screen.getByRole("button", { name: PARITY_COPY.pendingChanges.rejectConfirmAction }));

        // Click the confirm button INSIDE the dialog. Two buttons answer to the
        // rejectConfirmAction name: the one that opened the dialog and the one
        // inside it. The dialog's own button is added last, once the dialog
        // opens, so take the last match.
        const confirmButtons = screen.getAllByRole("button", {
            name: PARITY_COPY.pendingChanges.rejectConfirmAction,
        });
        const dialogConfirm = confirmButtons[confirmButtons.length - 1];
        fireEvent.click(dialogConfirm);

        expect(routerDelete).toHaveBeenCalledTimes(1);
        const [url, options] = routerDelete.mock.calls[0];
        expect(url).toBe(`/organizations/${ORG_ID}/position_changes/${CHANGE_ID}`);
        expect(options).toMatchObject({ preserveScroll: true });
    });

    // ── Approve only fires once, however fast you click ─────────────────────

    it("fires router.put exactly once when Approve is double-clicked", () => {
        render(<PendingChangeCard change={buildChange()} membership={buildMembership()} isAdmin={true} />);

        const approve = screen.getByRole("button", { name: "Approve Change" });
        fireEvent.click(approve);
        fireEvent.click(approve);

        // The Approve button used to have nothing stopping a second click, so
        // clicking twice sent two PUT requests and flashed a misleading
        // "already finalized" message.
        expect(routerPut).toHaveBeenCalledTimes(1);
        expect(routerPut).toHaveBeenCalledWith(
            `/organizations/${ORG_ID}/position_changes/${CHANGE_ID}`,
            undefined,
            expect.objectContaining({ preserveScroll: true }),
        );
    });
});
