import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href }: { children?: React.ReactNode; href?: string }) => <a href={href}>{children}</a>,
}));
vi.mock("app/frontend/components/bill/BillRowLink", () => ({
    default: ({ children }: { children?: React.ReactNode }) => <a href="/bills/101">{children}</a>,
}));
vi.mock("app/frontend/components/bill/BillEditLink", () => ({ default: () => null }));

import BillCard from "app/frontend/components/lists/BillCard";

const bill = (bill_score: Partial<sway.IBillScore>): sway.IBill =>
    ({
        id: 101,
        external_id: "26-0101",
        title: "Clean Air Act",
        summary: "Cleans the air.",
        categories: [],
        bill_score: {
            for: 7777,
            against: 4321,
            for_percent: 70,
            against_percent: 30,
            comparison_suppressed: false,
            voters_needed: 0,
            ...bill_score,
        },
    }) as unknown as sway.IBill;

// @lat: [[bill-list-layouts-design#Featured release dates on Past Bills of the Month]]
describe("lists/BillCard", () => {
    afterEach(cleanup);

    it("shows the For and Against percentages and never the counts", () => {
        const { container } = render(<BillCard bill={bill({})} />);

        expect(container.textContent).toContain("70%");
        expect(container.textContent).toContain("30%");
        expect(container.innerHTML).not.toMatch(/7,?777|4,?321/);
    });

    it("shows one line with no digit when the split is withheld", () => {
        const { container } = render(
            <BillCard bill={bill({ comparison_suppressed: true, for_percent: null, against_percent: null })} />,
        );

        expect(container.textContent).toContain("Not enough votes yet");
        expect(container.innerHTML).not.toMatch(/7,?777|4,?321/);
    });
});
