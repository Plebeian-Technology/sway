import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { vi, describe, it, expect, beforeEach } from "vitest";
import VoteComparisonPlaceholder from "../VoteComparisonPlaceholder";
import { usePage } from "@inertiajs/react";
import toast from "react-hot-toast";

vi.mock("@inertiajs/react", () => ({
    usePage: vi.fn<any>(),
    Link: ({ children, href }: any) => <a href={href}>{children}</a>,
}));

vi.mock("react-hot-toast", () => ({
    default: vi.fn<any>(),
}));

describe("VoteComparisonPlaceholder", () => {
    beforeEach(() => {
        vi.resetAllMocks();
        Object.assign(navigator, { clipboard: { writeText: vi.fn<any>() } });
    });

    it("renders 'Not enough votes yet' when votersNeeded is absent", () => {
        (usePage as any).mockReturnValue({ props: { user: undefined } });
        render(<VoteComparisonPlaceholder votersNeeded={undefined} />);
        expect(screen.getByText("Not enough votes yet")).toBeInTheDocument();
    });

    it("renders singular count when votersNeeded is 1", () => {
        (usePage as any).mockReturnValue({ props: { user: undefined } });
        render(<VoteComparisonPlaceholder votersNeeded={1} />);
        expect(screen.getByText("Visual comparisons will be shown when 1 more user has voted.")).toBeInTheDocument();
    });

    it("renders plural count when votersNeeded is > 1", () => {
        (usePage as any).mockReturnValue({ props: { user: undefined } });
        render(<VoteComparisonPlaceholder votersNeeded={3} />);
        expect(screen.getByText("Visual comparisons will be shown when 3 more users have voted.")).toBeInTheDocument();
    });

    it("renders sign-up link for signed-out users", () => {
        (usePage as any).mockReturnValue({ props: { user: undefined } });
        render(<VoteComparisonPlaceholder votersNeeded={3} />);
        const link = screen.getByRole("link", { name: /Share invite link/i });
        expect(link).toHaveAttribute("href", "/sign_up");
    });

    it("copies invite link for signed-in users and toasts success", async () => {
        const inviteUrl = "https://sway.vote/invite/123";
        (usePage as any).mockReturnValue({ props: { user: { invite_url: inviteUrl } } });
        render(<VoteComparisonPlaceholder votersNeeded={3} />);

        const button = screen.getByRole("button", { name: /Share invite link/i });
        fireEvent.click(button);

        await waitFor(() => {
            // eslint-disable-next-line
            expect(navigator.clipboard.writeText).toHaveBeenCalledWith(inviteUrl);
            expect(toast).toHaveBeenCalledWith("Bill link copied to clipboard.");
        });
    });

    it("renders no button when signed-in with null invite_url", () => {
        (usePage as any).mockReturnValue({ props: { user: { invite_url: null } } });
        render(<VoteComparisonPlaceholder votersNeeded={3} />);
        expect(screen.queryByRole("button")).not.toBeInTheDocument();
        expect(screen.queryByRole("link")).not.toBeInTheDocument();
    });
});
