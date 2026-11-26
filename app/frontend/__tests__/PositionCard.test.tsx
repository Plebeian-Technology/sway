// @lat: [[position-card-edit-field-snapshot-staleness#Why PositionCard reads props at Edit-click time, not at mount]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const routerPut = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        put: (...args: unknown[]) => routerPut(...args),
        delete: vi.fn<(...args: unknown[]) => void>(),
    },
    Link: ({ href, children }: { href: string; children: React.ReactNode }) => <a href={href}>{children}</a>,
}));

vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<() => Promise<boolean>>().mockResolvedValue(false),
}));

import PositionCard from "app/frontend/components/organizations/PositionCard";

type CardProps = React.ComponentProps<typeof PositionCard>;

const buildPosition = (overrides: Record<string, unknown> = {}): CardProps["position"] =>
    ({
        id: 100,
        bill_id: 9,
        support: "FOR",
        summary: "v1",
        bill: { id: 9, external_id: "HB-1", title: "Test Bill" },
        locked: false,
        ...overrides,
    }) as unknown as CardProps["position"];

afterEach(() => {
    cleanup();
    routerPut.mockReset();
});

describe("PositionCard — edit state seeds at Edit click", () => {
    it("shows the latest server summary in the textarea when Edit is clicked after a prop update", () => {
        const { rerender } = render(
            <PositionCard
                position={buildPosition({ summary: "v1" })}
                organizationId={7}
                organizationName="Bikemore"
                isAdmin
            />,
        );

        // A partial reload brings newer server data while the card stays up.
        rerender(
            <PositionCard
                position={buildPosition({ summary: "v2" })}
                organizationId={7}
                organizationName="Bikemore"
                isAdmin
            />,
        );

        fireEvent.click(screen.getByRole("button", { name: /edit/i }));

        const textarea = screen.getByLabelText("Summary") as HTMLTextAreaElement;
        expect(textarea.value).toBe("v2");
    });

    it("shows an empty textarea for a Neutral position, which carries no testimony", () => {
        render(
            <PositionCard
                position={buildPosition({ support: "ABSTAIN", summary: null })}
                organizationId={7}
                organizationName="Bikemore"
                isAdmin
            />,
        );

        fireEvent.click(screen.getByRole("button", { name: /edit/i }));

        const textarea = screen.getByLabelText("Summary") as HTMLTextAreaElement;
        expect(textarea.value).toBe("");
    });
});
