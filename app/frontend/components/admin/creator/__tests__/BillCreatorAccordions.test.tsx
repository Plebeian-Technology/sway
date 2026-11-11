import type { Dispatch, SetStateAction } from "react";
import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockPageProps: {
    bill?: { id: number; [key: string]: unknown };
    legislator_votes?: Array<{ legislator_id: number; support: string }>;
} = {};
let mockPageUrl = "/admin/bill_creator/42/creator";

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({ props: mockPageProps, url: mockPageUrl }),
}));

vi.mock("app/frontend/components/admin/creator/BillCreatorBillForm", () => ({
    default: () => <div data-testid="bill-form-panel">Bill Form Content</div>,
}));

vi.mock("app/frontend/components/admin/creator/BillCreatorLegislatorVotes", () => ({
    default: () => <div data-testid="legislator-votes-panel">Legislator Votes Content</div>,
}));

vi.mock("app/frontend/components/admin/creator/BillCreatorOrganizations", () => ({
    default: () => <div data-testid="organizations-panel">Organizations Content</div>,
}));

vi.mock("app/frontend/components/admin/creator/FeatureInfo", () => ({
    default: ({ note }: { note: string }) => <span data-testid={`feature-info-${note}`} />,
}));

import BillCreatorAccordions from "app/frontend/components/admin/creator/BillCreatorAccordions";

describe("BillCreatorAccordions — mobile responsive navigation", () => {
    beforeEach(() => {
        delete mockPageProps.bill;
        delete mockPageProps.legislator_votes;
        mockPageUrl = "/admin/bill_creator/42/creator";
    });

    // @lat: [[bill-creator-shell#How the frame adapts to phone browser viewports]]
    it("renders all 4 accordions with min-h-11 touch targets and open-state styles", () => {
        render(<BillCreatorAccordions setCreatorDirty={vi.fn<Dispatch<SetStateAction<boolean>>>()} />);

        const triggers = screen.getAllByRole("button");
        const accordionTriggers = triggers.filter((btn) => btn.getAttribute("data-slot") === "accordion-trigger");
        expect(accordionTriggers).toHaveLength(4);

        for (const trigger of accordionTriggers) {
            expect(trigger.className).toContain("min-h-11");
            expect(trigger.className).toContain("data-[state=open]:text-primary");
            expect(trigger.className).toContain("data-[state=open]:bg-accent/10");
        }
    });

    it("disables subsequent accordions when no bill is active", () => {
        render(<BillCreatorAccordions setCreatorDirty={vi.fn<Dispatch<SetStateAction<boolean>>>()} />);

        const detailsTrigger = screen.getByRole("button", { name: /Details and Summary/i });
        const votesTrigger = screen.getByRole("button", { name: /Legislator Votes/i });
        const orgsTrigger = screen.getByRole("button", { name: /Supporting\/Opposing Arguments/i });
        const llmTrigger = screen.getByRole("button", { name: /LLM Summary/i });

        expect(detailsTrigger).not.toBeDisabled();
        expect(votesTrigger).toBeDisabled();
        expect(orgsTrigger).toBeDisabled();
        expect(llmTrigger).toBeDisabled();
    });

    it("enables all accordions when a bill exists", () => {
        mockPageProps.bill = { id: 42 };
        render(<BillCreatorAccordions setCreatorDirty={vi.fn<Dispatch<SetStateAction<boolean>>>()} />);

        const detailsTrigger = screen.getByRole("button", { name: /Details and Summary/i });
        const votesTrigger = screen.getByRole("button", { name: /Legislator Votes/i });
        const orgsTrigger = screen.getByRole("button", { name: /Supporting\/Opposing Arguments/i });
        const llmTrigger = screen.getByRole("button", { name: /LLM Summary/i });

        expect(detailsTrigger).not.toBeDisabled();
        expect(votesTrigger).not.toBeDisabled();
        expect(orgsTrigger).not.toBeDisabled();
        expect(llmTrigger).not.toBeDisabled();
    });

    it("toggles open state and visual feedback on click", async () => {
        mockPageProps.bill = { id: 42 };
        render(<BillCreatorAccordions setCreatorDirty={vi.fn<Dispatch<SetStateAction<boolean>>>()} />);

        const detailsTrigger = screen.getByRole("button", { name: /Details and Summary/i });
        const votesTrigger = screen.getByRole("button", { name: /Legislator Votes/i });

        // Initially Details and Summary is open by default
        expect(detailsTrigger).toHaveAttribute("data-state", "open");
        expect(votesTrigger).toHaveAttribute("data-state", "closed");

        // Clicking votes accordion opens it and closes details
        fireEvent.click(votesTrigger);

        expect(votesTrigger).toHaveAttribute("data-state", "open");
        expect(detailsTrigger).toHaveAttribute("data-state", "closed");
    });

    it("syncs open accordion section when event_key changes in page.url across redirects", () => {
        mockPageProps.bill = { id: 42 };
        const { rerender } = render(
            <BillCreatorAccordions setCreatorDirty={vi.fn<Dispatch<SetStateAction<boolean>>>()} />,
        );

        const orgsTrigger = screen.getByRole("button", { name: /Supporting\/Opposing Arguments/i });
        expect(orgsTrigger).toHaveAttribute("data-state", "closed");

        mockPageUrl = "/admin/bill_creator/42/creator?event_key=organizations";
        rerender(<BillCreatorAccordions setCreatorDirty={vi.fn<Dispatch<SetStateAction<boolean>>>()} />);

        expect(orgsTrigger).toHaveAttribute("data-state", "open");
    });
});
