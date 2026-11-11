import { act, renderHook, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

// ── Module mocks ────────────────────────────────────────────────────────────

const post = vi.fn<(url: string, options: { onSuccess?: () => void; onError?: () => void }) => void>();
const routerFlushAll = vi.fn<() => void>();

let mockUser: Partial<sway.IUser> | null = { id: 1, full_name: "Test User" } as any;
let mockPendingVote: { bill_id: number; support: sway.TUserSupport } | null = null;

// @lat: [[user-vote-submission#Submission hooks]]
vi.mock("@inertiajs/react", () => ({
    usePage: () => ({
        props: {
            user: mockUser,
            pending_vote: mockPendingVote,
            errors: {},
        },
    }),
    Link: ({ href, children, ...props }: any) => (
        <a href={href} {...props}>
            {children}
        </a>
    ),
    router: {
        post: vi.fn<(...args: unknown[]) => void>(),
        get: vi.fn<(...args: unknown[]) => void>(),
        reload: vi.fn<(...args: unknown[]) => void>(),
        flushAll: () => routerFlushAll(),
    },
    useHttp: () => ({
        transform: vi.fn<(...args: unknown[]) => unknown>(),
        post: vi.fn<(...args: unknown[]) => void>(),
        put: vi.fn<(...args: unknown[]) => void>(),
        processing: false,
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

const confirmMock = vi.fn<() => Promise<boolean>>();
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({ useConfirm: () => confirmMock }));

const offline = { isOnline: true, assertBanner: vi.fn<() => void>() };
vi.mock("app/frontend/components/contexts/hooks/useOffline", () => ({ useOffline: () => offline }));

const notify = vi.fn<(message: unknown) => void>();
vi.mock("app/frontend/sway_utils", async (importOriginal) => ({
    ...(await importOriginal<typeof import("app/frontend/sway_utils")>()),
    notify: (message: unknown) => notify(message),
}));

import { useCastUserVote } from "app/frontend/components/bill/hooks/useCastUserVote";
import VotePanel from "app/frontend/components/bill/VotePanel";

// ── Helpers ─────────────────────────────────────────────────────────────────

const BILL = { id: 7, external_id: "HB0042", title: "A Bill" } as sway.IBill;

const renderPanel = (user_vote?: sway.IUserVote | null) => render(<VotePanel bill={BILL} user_vote={user_vote} />);

const forButton = () => screen.getByRole("button", { name: /Support this legislation/ });
const againstButton = () => screen.getByRole("button", { name: /Oppose this legislation/ });

// ── Tests ───────────────────────────────────────────────────────────────────

describe("VotePanel", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        offline.isOnline = true;
    });
    afterEach(cleanup);

    it("renders a For and an Against vote button", () => {
        renderPanel();
        expect(forButton()).toBeInTheDocument();
        expect(againstButton()).toBeInTheDocument();
    });

    it("shows the recorded vote and disables both buttons once the user has voted", () => {
        const { container } = renderPanel({ support: "FOR" } as sway.IUserVote);
        expect(container.textContent).toContain("You recorded a For vote on this bill.");
        expect(forButton()).toBeDisabled();
        expect(againstButton()).toBeDisabled();
    });

    it("leaves both buttons enabled when no vote is recorded", () => {
        renderPanel();
        expect(forButton()).toBeEnabled();
        expect(againstButton()).toBeEnabled();
    });

    it("disables both buttons when the bill is inactive and unscheduled (archived historical session)", () => {
        render(<VotePanel bill={{ ...BILL, active: false }} />);
        expect(forButton()).toBeDisabled();
        expect(againstButton()).toBeDisabled();
    });

    it("enables voting for a signed-in user on an unarchived Past Bill of the Month from a prior session", () => {
        render(<VotePanel bill={{ ...BILL, active: false, scheduled_release_date_utc: "2024-05-01" }} />);
        expect(forButton()).toBeEnabled();
        expect(againstButton()).toBeEnabled();
    });

    it("asks for confirmation before casting a vote", async () => {
        confirmMock.mockResolvedValue(false);
        renderPanel();
        fireEvent.click(forButton());
        await waitFor(() => expect(confirmMock).toHaveBeenCalledTimes(1));
        expect(confirmMock).toHaveBeenCalledWith(
            expect.objectContaining({
                title: "This vote is final",
                confirmLabel: "Cast vote",
                tone: "destructive",
            }),
        );
    });

    it("closes without a toast and does not POST when confirmation is dismissed", async () => {
        confirmMock.mockResolvedValue(false);
        renderPanel();
        fireEvent.click(forButton());
        await waitFor(() => expect(confirmMock).toHaveBeenCalledTimes(1));
        expect(post).not.toHaveBeenCalled();
        expect(notify).not.toHaveBeenCalled();
    });

    it("POSTs the vote to /user_votes once the confirmation is accepted", async () => {
        confirmMock.mockResolvedValue(true);
        renderPanel();
        fireEvent.click(againstButton());
        await waitFor(() => expect(post).toHaveBeenCalledWith("/user_votes", expect.any(Object)));
    });

    it("surfaces the offline message and does not POST when offline", async () => {
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
        post.mockImplementation((_url, options) => options.onSuccess?.());
        renderPanel();
        fireEvent.click(forButton());
        await waitFor(() =>
            expect(notify).toHaveBeenCalledWith(
                expect.objectContaining({ level: "success", title: "Vote on bill HB0042 cast!" }),
            ),
        );
        expect(screen.getByTestId("vote-announcement")).toHaveTextContent("You recorded a For vote on this bill.");
    });

    it("clears the pending vote when its successful request completes", async () => {
        post.mockImplementation(() => {});
        confirmMock.mockResolvedValue(true);
        const { result } = renderHook(() => useCastUserVote(BILL));
        act(() => result.current.handleChoice("FOR"));
        await waitFor(() => expect(result.current.pendingSupport).toBe("FOR"));
        act(() => post.mock.calls[0][1].onSuccess?.());
        expect(result.current.pendingSupport).toBeNull();
        expect(result.current.voteRecorded).toBe("FOR");
    });

    it("notifies an error when the vote POST fails", async () => {
        confirmMock.mockResolvedValue(true);
        post.mockImplementation((_url, options) => options.onError?.());
        renderPanel();
        fireEvent.click(forButton());
        await waitFor(() =>
            expect(notify).toHaveBeenCalledWith(
                expect.objectContaining({ level: "error", title: "Error saving vote." }),
            ),
        );
    });

    // @lat: [[user-vote-submission#Submission hooks]]
    it("rolls the optimistic vote back and re-enables the buttons when the POST fails", async () => {
        confirmMock.mockResolvedValue(true);
        post.mockImplementation((_url, options) => options.onError?.());
        renderPanel(); // no prior vote
        fireEvent.click(forButton());

        await waitFor(() => expect(notify).toHaveBeenCalledWith(expect.objectContaining({ level: "error" })));
        await waitFor(() => expect(forButton()).toBeEnabled());
        expect(againstButton()).toBeEnabled();
        expect(screen.queryByText(/You recorded/)).toBeNull();
    });
});

// @lat: [[vote-panel-announcements#What a screen reader hears when a vote is cast]]
describe("VotePanel — what a screen reader is told", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        // clearAllMocks leaves an implementation set by an earlier test in place.
        post.mockReset();
        offline.isOnline = true;
    });
    afterEach(cleanup);

    it("announces the recorded vote through an announcer that is always in the tree", () => {
        renderPanel({ support: "FOR" } as sway.IUserVote);

        const announcer = screen.getByTestId("vote-announcement");
        expect(announcer).toBe(screen.getByRole("status"));
        expect(announcer.className).toContain("sr-only");
        expect(announcer.textContent).toBe("You recorded a For vote on this bill.");
    });

    it("announces the vote a reader has just cast", async () => {
        confirmMock.mockResolvedValue(true);
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() =>
            expect(screen.getByTestId("vote-announcement").textContent).toBe("You recorded a For vote on this bill."),
        );
    });

    it("keeps the announcer in the page, and visible to the accessibility tree, with nothing to say", () => {
        renderPanel();

        const announcer = screen.getByTestId("vote-announcement");
        expect(announcer).toBe(screen.getByRole("status"));
        expect(announcer.textContent).toBe("");
        // sr-only clips the announcer; it never removes it from the tree, which
        // is what would stop the announcement arriving with the text.
        expect(announcer.className).not.toContain("hidden");
    });

    it("no longer watches the button grid for changes", () => {
        renderPanel({ support: "FOR" } as sway.IUserVote);

        expect(screen.getByTestId("vote-recorded").getAttribute("aria-live")).toBeNull();
        expect(forButton().closest("[aria-live]")).toBeNull();
    });
});

// @lat: [[low-friction-voting#Provisional vote capture and cookie lifecycle]]
describe("VotePanel — unauthenticated provisional voting", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        routerFlushAll.mockReset();
        mockUser = null;
        mockPendingVote = null;
        offline.isOnline = true;
        globalThis.fetch = vi.fn<(...args: unknown[]) => Promise<Response>>().mockResolvedValue({
            ok: true,
            json: async () => ({ ok: true, pending_vote: { bill_id: BILL.id, support: "FOR" } }),
        } as Response);
    });

    afterEach(() => {
        mockUser = { id: 1, full_name: "Test User" } as any;
        cleanup();
    });

    it("bypasses confirmation dialog and posts to /provisional_votes when signed out", async () => {
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() => {
            expect(globalThis.fetch).toHaveBeenCalledWith(
                "/provisional_votes",
                expect.objectContaining({
                    method: "POST",
                    body: JSON.stringify({ bill_id: BILL.id, support: "FOR" }),
                }),
            );
        });
        expect(confirmMock).not.toHaveBeenCalled();
    });

    it("renders provisional amber styling on the selected button", async () => {
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() => {
            expect(forButton().className).toContain("border-amber-500");
        });
    });

    it("renders the reassuring banner and civic disclaimer after provisional selection", async () => {
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() => {
            const banner = screen.getByTestId("provisional-vote-banner");
            expect(banner).toBeInTheDocument();
            expect(banner.textContent).toContain("Your vote is saved! Complete quick registration");
            expect(banner.textContent).toContain(
                "Pending constituent verification — not yet included in official tallies.",
            );
            expect(banner.textContent).not.toContain("Maryland");
        });
    });

    it("opens the registration modal on successful provisional vote", async () => {
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() => {
            expect(screen.getByTestId("provisional-registration-modal")).toBeInTheDocument();
        });
    });

    it("initializes in provisional state when pending_vote cookie is in page props for this bill", () => {
        mockPendingVote = { bill_id: BILL.id, support: "FOR" };
        renderPanel();

        expect(forButton().className).toContain("border-amber-500");
        expect(screen.getByTestId("provisional-vote-banner")).toBeInTheDocument();
    });

    it("flushes the Inertia prefetch cache after provisional vote succeeds", async () => {
        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() => {
            expect(routerFlushAll).toHaveBeenCalledTimes(1);
        });
    });

    it("does not flush the Inertia prefetch cache when provisional vote fails", async () => {
        globalThis.fetch = vi.fn<(...args: unknown[]) => Promise<Response>>().mockResolvedValue({
            ok: false,
            status: 500,
            json: async () => ({ error: "Server error" }),
        } as Response);

        renderPanel();
        fireEvent.click(forButton());

        await waitFor(() => {
            expect(notify).toHaveBeenCalledWith(
                expect.objectContaining({ level: "error", title: "Error saving provisional vote." }),
            );
        });
        expect(routerFlushAll).not.toHaveBeenCalled();
    });
});
