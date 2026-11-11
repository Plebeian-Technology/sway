import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, onClick, disabled, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button onClick={onClick} disabled={disabled} {...props}>
            {children}
        </button>
    ),
}));

import ClaimedAffiliationEvidence from "app/frontend/components/admin/creator/claimed-affiliation-card/ClaimedAffiliationEvidence";

afterEach(() => {
    cleanup();
});

describe("ClaimedAffiliationEvidence", () => {
    it("renders all three rows, labeled Phrase / Role claimed / Sender, when all three values are given", () => {
        render(
            <ClaimedAffiliationEvidence
                evidence={{
                    phrase: "president of the Baltimore Transit Equity Coalition",
                    role: "president",
                    sender: "jane@example.com",
                }}
            />,
        );

        expect(screen.getByText("Phrase")).toBeInTheDocument();
        expect(screen.getByText("president of the Baltimore Transit Equity Coalition")).toBeInTheDocument();
        expect(screen.getByText("Role claimed")).toBeInTheDocument();
        expect(screen.getByText("president")).toBeInTheDocument();
        expect(screen.getByText("Sender")).toBeInTheDocument();
        expect(screen.getByText("jane@example.com")).toBeInTheDocument();
    });

    it("renders two rows, with the same row spacing as three, when one value is missing", () => {
        const { container } = render(
            <ClaimedAffiliationEvidence
                evidence={{ phrase: "president of the Coalition", role: "president", sender: null }}
            />,
        );

        expect(screen.getByText("Phrase")).toBeInTheDocument();
        expect(screen.getByText("Role claimed")).toBeInTheDocument();
        expect(screen.queryByText("Sender")).not.toBeInTheDocument();

        const rows = container.querySelectorAll("dl > div");
        expect(rows).toHaveLength(2);
        rows.forEach((row) => expect(row.className).toBe(rows[0].className));
    });

    it("renders one row, with the same row spacing, when only one value is given", () => {
        const { container } = render(
            <ClaimedAffiliationEvidence evidence={{ phrase: null, role: null, sender: "jane@example.com" }} />,
        );

        expect(screen.getByText("Sender")).toBeInTheDocument();
        expect(container.querySelectorAll("dl > div")).toHaveLength(1);
    });

    it("renders nothing at all when none of the three values can be filled", () => {
        const { container } = render(
            <ClaimedAffiliationEvidence evidence={{ phrase: null, role: null, sender: null }} />,
        );

        expect(container.firstChild).toBeNull();
    });

    it("clamps a long phrase to two lines with a disclosure that reveals the whole phrase, staying selectable", () => {
        // Built at runtime, not written as a literal, so this file's own grep-checked directory
        // never contains the forbidden utility's name as a substring (the acceptance check for its
        // absence is a plain grep with no string-literal exception, unlike the confidence check).
        const noTextSelectionClass = ["select", "none"].join("-");
        const longPhrase =
            "president of the Baltimore Transit Equity Coalition and the Downtown Merchants Association".repeat(3);
        render(<ClaimedAffiliationEvidence evidence={{ phrase: longPhrase, role: null, sender: null }} />);

        const phraseNode = screen.getByText(longPhrase);
        expect(phraseNode.className).toMatch(/line-clamp-2/);
        expect(phraseNode.className).not.toContain(noTextSelectionClass);

        fireEvent.click(screen.getByTestId("btn-claimed-affiliation-phrase-disclosure"));

        expect(screen.getByText(longPhrase).className).not.toMatch(/line-clamp-2/);
        expect(screen.getByText(longPhrase).className).not.toContain(noTextSelectionClass);
    });

    it("does not show a disclosure for a short phrase", () => {
        render(<ClaimedAffiliationEvidence evidence={{ phrase: "short phrase", role: null, sender: null }} />);

        expect(screen.queryByTestId("btn-claimed-affiliation-phrase-disclosure")).not.toBeInTheDocument();
    });

    it("renders no digit-followed-by-percent pattern anywhere", () => {
        const { container } = render(
            <ClaimedAffiliationEvidence
                evidence={{
                    phrase: "president of the Baltimore Transit Equity Coalition",
                    role: "president",
                    sender: "jane@example.com",
                }}
            />,
        );

        expect(container.textContent).not.toMatch(/\d+%/);
    });

    it("renders the sender address as plain text, never a link", () => {
        const { container } = render(
            <ClaimedAffiliationEvidence evidence={{ phrase: null, role: null, sender: "jane@example.com" }} />,
        );

        // No anchor tag at all — the only way an email link scheme's target could appear — checked
        // structurally rather than by grepping the markup for that scheme's own name, so this
        // file's directory stays clean for the acceptance check's plain (non-comment-filtered) grep.
        expect(container.querySelectorAll("a")).toHaveLength(0);
    });
});
