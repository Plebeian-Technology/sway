import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

const useUserMock = vi.fn<() => sway.IUser | null | undefined>();
const copyMock = vi.fn<(text: string) => Promise<boolean>>(() => Promise.resolve(true));
const notifyMock = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    Link: ({ href, children, className }: { href: string; children: React.ReactNode; className?: string }) => (
        <a href={href} className={className}>
            {children}
        </a>
    ),
}));

vi.mock("app/frontend/hooks/users/useUser", () => ({
    useUser: () => useUserMock(),
}));

vi.mock("copy-to-clipboard", () => ({
    default: (text: string) => copyMock(text),
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => notifyMock(...args),
}));

import VoteComparisonPlaceholder from "app/frontend/components/bill/VoteComparisonPlaceholder";
import { ROUTES } from "app/frontend/sway_constants/routes";

const INVITE_URL = "https://app.example.test/invite/7/abc";
const signedInUser = (invite_url: string | null) => ({ id: 7, invite_url }) as unknown as sway.IUser;

// @lat: [[voter-privacy-threshold#The placeholder shown in place of a hidden comparison]]
describe("VoteComparisonPlaceholder", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        useUserMock.mockReturnValue(signedInUser(INVITE_URL));
    });

    afterEach(() => {
        cleanup();
    });

    it("says how many more users are needed, then asks the reader to invite others", () => {
        render(<VoteComparisonPlaceholder votersNeeded={3} />);

        expect(screen.getByText("Visual comparisons will be shown when 3 more users have voted.")).toBeInTheDocument();
        expect(screen.getByText("Invite others by sharing Sway")).toBeInTheDocument();
    });

    it("uses the singular when one more user is needed", () => {
        render(<VoteComparisonPlaceholder votersNeeded={1} />);

        expect(screen.getByText("Visual comparisons will be shown when 1 more user has voted.")).toBeInTheDocument();
    });

    it("says only 'Not enough votes yet' when the number of voters needed is not sent", () => {
        render(<VoteComparisonPlaceholder />);

        expect(screen.getByText("Not enough votes yet")).toBeInTheDocument();
        expect(screen.queryByText(/Visual comparisons will be shown/)).not.toBeInTheDocument();
    });

    it("copies a signed-in user's invite link and confirms it", async () => {
        render(<VoteComparisonPlaceholder votersNeeded={3} />);

        fireEvent.click(screen.getByRole("button", { name: "Copy invite link" }));

        await waitFor(() => {
            expect(notifyMock).toHaveBeenCalledWith({ level: "info", title: "Invite link copied to clipboard." });
        });
        expect(copyMock).toHaveBeenCalledWith(INVITE_URL);
    });

    it("links a signed-out visitor to sign-up", () => {
        useUserMock.mockReturnValue(null);

        render(<VoteComparisonPlaceholder votersNeeded={3} />);

        expect(screen.getByRole("link", { name: "Sign up" })).toHaveAttribute("href", ROUTES.signin);
        expect(screen.queryByRole("button")).not.toBeInTheDocument();
    });

    it("shows the message without a button when a signed-in user has no invite link", () => {
        useUserMock.mockReturnValue(signedInUser(null));

        render(<VoteComparisonPlaceholder votersNeeded={3} />);

        expect(screen.getByText("Visual comparisons will be shown when 3 more users have voted.")).toBeInTheDocument();
        expect(screen.queryByRole("button")).not.toBeInTheDocument();
        expect(screen.queryByRole("link")).not.toBeInTheDocument();
    });
});
