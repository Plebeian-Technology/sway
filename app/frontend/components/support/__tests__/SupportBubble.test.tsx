import { fireEvent, render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import SupportBubble from "app/frontend/components/support/SupportBubble";

describe("SupportBubble", () => {
    it("opens the privacy walkthrough dialog with the schedule mailto link and closes on Escape", () => {
        render(<SupportBubble />);

        const trigger = screen.getByRole("button", { name: "Support" });
        expect(trigger).toBeInTheDocument();
        expect(screen.queryByRole("dialog")).not.toBeInTheDocument();

        fireEvent.click(trigger);

        const dialog = screen.getByRole("dialog", { name: "Request a privacy walkthrough" });
        expect(dialog).toBeInTheDocument();
        expect(within(dialog).getByRole("heading", { name: "Request a privacy walkthrough" })).toBeInTheDocument();
        expect(
            within(dialog).getByText(
                /privacy walkthroughs over video chat.*the app, the database, and, with your permission, your own account data/i,
            ),
        ).toBeInTheDocument();

        const scheduleLink = within(dialog).getByRole("link", { name: "Email us to schedule" });
        expect(scheduleLink).toHaveAttribute("href", "mailto:info@sway.vote?subject=Privacy%20walkthrough%20request");

        fireEvent.keyDown(document.activeElement!, { key: "Escape" });

        expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    });

    it("closes the dialog when clicking the close button", () => {
        render(<SupportBubble />);

        fireEvent.click(screen.getByRole("button", { name: "Support" }));

        const dialog = screen.getByRole("dialog", { name: "Request a privacy walkthrough" });
        fireEvent.click(within(dialog).getByRole("button", { name: "Close" }));

        expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    });
});
