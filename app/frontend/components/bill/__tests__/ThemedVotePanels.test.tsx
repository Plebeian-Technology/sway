import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

// ── Module mocks (mirrors VotePanel.test.tsx — the panels share useCastUserVote) ──

const post = vi.fn<(url: string, options?: { onSuccess?: () => void; onError?: () => void }) => void>();
let mockUser: { id: number; full_name: string } | null = { id: 1, full_name: "Test User" };
let mockPendingVote: { bill_id: number; support: string } | null = null;
const routerFlushAll = vi.fn<() => void>();

// A useForm stand-in that really holds state: setData("support", value) merges
// into that state, so the vote written straight away — and its undo when the
// server refuses — both show up in the rendered aria-pressed and disabled
// attributes.
vi.mock("@inertiajs/react", () => ({
    router: {
        flushAll: () => routerFlushAll(),
    },
    usePage: () => ({
        props: {
            user: mockUser,
            pending_vote: mockPendingVote,
        },
    }),
    useForm: function useForm(initial: Record<string, unknown>) {
        const [data, setDataState] = React.useState<Record<string, unknown>>(initial ?? {});
        const setData = (key: string, value: unknown) => setDataState((prev) => ({ ...prev, [key]: value }));
        return {
            data,
            setData,
            post,
            processing: false,
            transform: vi.fn<(data: Record<string, unknown>) => Record<string, unknown>>(),
        };
    },
}));

vi.mock("app/frontend/components/bill/ProvisionalRegistrationModal", () => ({
    default: ({ open, provisionalSupport }: { open: boolean; provisionalSupport?: string | null }) =>
        open ? <div data-testid="provisional-registration-modal">{provisionalSupport}</div> : null,
}));

const confirmMock = vi.fn<(opts: Record<string, unknown>) => Promise<boolean>>();
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({ useConfirm: () => confirmMock }));

const offline = { isOnline: true, assertBanner: vi.fn<() => void>() };
vi.mock("app/frontend/components/contexts/hooks/useOffline", () => ({ useOffline: () => offline }));

const notify = vi.fn<(opts: Record<string, unknown>) => void>();
vi.mock("app/frontend/sway_utils", async (importOriginal) => ({
    ...(await importOriginal<typeof import("app/frontend/sway_utils")>()),
    notify: (opts: Record<string, unknown>) => notify(opts),
}));

import BallotVotePanel from "app/frontend/components/bill/BallotVotePanel";
import CornerstoreVotePanel from "app/frontend/components/bill/CornerstoreVotePanel";

const BILL = { id: 7, external_id: "HB0042", title: "A Bill" } as sway.IBill;

const forButton = () => screen.getByRole("button", { name: /Support this legislation/ });
const againstButton = () => screen.getByRole("button", { name: /Oppose this legislation/ });

// Both themed controls offer the SAME action in different clothing: a filled-in
// ballot oval and a pressed poster block. What follows is what has to be true of
// both of them, whatever they look like.
const PANELS = [
    { name: "BallotVotePanel", Panel: BallotVotePanel },
    { name: "CornerstoreVotePanel", Panel: CornerstoreVotePanel },
] as const;

describe.each(PANELS)("$name", ({ Panel }) => {
    const renderPanel = (user_vote?: sway.IUserVote | null) => render(<Panel bill={BILL} user_vote={user_vote} />);

    beforeEach(() => {
        vi.clearAllMocks();
        offline.isOnline = true;
        mockUser = { id: 1, full_name: "Test User" };
        mockPendingVote = null;
    });
    afterEach(cleanup);

    it("exposes For and Against as real buttons with the shared accessible names", () => {
        renderPanel();
        expect(forButton()).toBeInTheDocument();
        expect(againstButton()).toBeInTheDocument();
    });

    // A cast vote has to be announced to screen readers, not shown by fill
    // colour alone.
    it("marks only the chosen side aria-pressed and disables both once voted", () => {
        renderPanel({ support: "FOR" } as sway.IUserVote);

        expect(forButton()).toHaveAttribute("aria-pressed", "true");
        expect(againstButton()).toHaveAttribute("aria-pressed", "false");
        expect(forButton()).toBeDisabled();
        expect(againstButton()).toBeDisabled();
    });

    it("leaves both buttons enabled and unpressed when no vote is recorded", () => {
        renderPanel();
        expect(forButton()).toBeEnabled();
        expect(forButton()).toHaveAttribute("aria-pressed", "false");
        expect(againstButton()).toBeEnabled();
    });

    it("renders the recorded state as text, and only on the side that was cast", () => {
        renderPanel({ support: "FOR" } as sway.IUserVote);

        // The announcer carries the same sentence, so the visible receipt is the
        // match that is not sr-only.
        const visibleReceipt = screen
            .getAllByText("You recorded a For vote on this bill.")
            .find((node) => !node.className.includes("sr-only"));
        expect(visibleReceipt).toBeTruthy();
        // The stamp/mark is real text inside the chosen control...
        expect(within(forButton()).getByText(/Recorded/)).toBeInTheDocument();
        // ...and it is not on the page at all on the other side, so it can
        // never be read out when the styling is missing.
        expect(within(againstButton()).queryByText(/Recorded/)).toBeNull();
    });

    it("asks for confirmation before casting", async () => {
        confirmMock.mockResolvedValue(false);
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() => expect(confirmMock).toHaveBeenCalledTimes(1));
        expect(confirmMock).toHaveBeenCalledWith(expect.objectContaining({ confirmLabel: "Cast vote" }));
        expect(post).not.toHaveBeenCalled();
    });

    it("POSTs to /user_votes once the confirmation is accepted", async () => {
        confirmMock.mockResolvedValue(true);
        renderPanel();
        fireEvent.click(againstButton());

        await waitFor(() => expect(post).toHaveBeenCalledWith("/user_votes", expect.any(Object)));
    });

    it("surfaces the offline alert and does not POST when offline", async () => {
        confirmMock.mockResolvedValue(true);
        offline.isOnline = false;
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() => expect(screen.getByRole("alert")).toBeInTheDocument());
        expect(post).not.toHaveBeenCalled();
        expect(offline.assertBanner).toHaveBeenCalled();
    });

    it("announces the saved vote and notifies success after a successful POST", async () => {
        confirmMock.mockResolvedValue(true);
        post.mockImplementation((_url, options) => options?.onSuccess?.());
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() =>
            expect(notify).toHaveBeenCalledWith(
                expect.objectContaining({ level: "success", title: "Vote on bill HB0042 cast!" }),
            ),
        );
        expect(screen.getByTestId("vote-announcement")).toHaveTextContent("You recorded a For vote on this bill.");
    });

    // @lat: [[vote-panel-announcements#What a screen reader hears when a vote is cast]]
    it("announces the recorded vote through an announcer that is always in the tree", () => {
        renderPanel({ support: "FOR" } as sway.IUserVote);

        const announcer = screen.getByTestId("vote-announcement");
        expect(announcer).toBe(screen.getByRole("status"));
        expect(announcer.className).toContain("sr-only");
        expect(announcer.textContent).toBe("You recorded a For vote on this bill.");
    });

    it("keeps the announcer in the page, and visible to the accessibility tree, with nothing to say", () => {
        renderPanel();

        const announcer = screen.getByTestId("vote-announcement");
        expect(announcer).toBe(screen.getByRole("status"));
        expect(announcer.textContent).toBe("");
        expect(announcer.className).not.toContain("hidden");
    });

    it("announces the vote a reader has just cast", async () => {
        confirmMock.mockResolvedValue(true);
        post.mockReset();
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() =>
            expect(screen.getByTestId("vote-announcement").textContent).toBe("You recorded a For vote on this bill."),
        );
    });

    it("no longer watches the button row for changes", () => {
        renderPanel({ support: "FOR" } as sway.IUserVote);

        expect(screen.getByTestId("vote-recorded").getAttribute("aria-live")).toBeNull();
        expect(forButton().closest("[aria-live]")).toBeNull();
    });

    it("rolls the optimistic vote back and re-enables both buttons when the POST fails", async () => {
        confirmMock.mockResolvedValue(true);
        post.mockImplementation((_url, options) => options?.onError?.());
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() => expect(notify).toHaveBeenCalledWith(expect.objectContaining({ level: "error" })));
        await waitFor(() => expect(forButton()).toBeEnabled());
        expect(againstButton()).toBeEnabled();
        expect(screen.queryByText(/You recorded/)).toBeNull();
    });

    it("renders provisional vote banner for unauthenticated users and restores previous provisional support on failed POST", async () => {
        mockUser = null;
        mockPendingVote = { bill_id: 7, support: "FOR" };
        const fetchMock = vi.fn<() => Promise<{ ok: boolean }>>().mockResolvedValueOnce({ ok: false });
        vi.stubGlobal("fetch", fetchMock);

        renderPanel();

        expect(screen.getByTestId("provisional-vote-banner")).toHaveTextContent(/Your vote is saved!/i);
        fireEvent.click(screen.getByRole("button", { name: /Complete registration/i }));
        expect(screen.getByTestId("provisional-registration-modal")).toHaveTextContent("FOR");

        fireEvent.click(againstButton());

        await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
        await waitFor(() => expect(screen.getByTestId("provisional-registration-modal")).toHaveTextContent("FOR"));

        vi.unstubAllGlobals();
    });
});
