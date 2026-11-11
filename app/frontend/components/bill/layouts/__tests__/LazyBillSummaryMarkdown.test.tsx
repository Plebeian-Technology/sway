import { readFileSync } from "fs";
import { resolve } from "path";

import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";

import LazyBillSummaryMarkdown from "app/frontend/components/bill/layouts/LazyBillSummaryMarkdown";

const BILL_DIR = resolve(__dirname, "../..");

const SUMMARY_RENDERERS = [
    "layouts/BallotBillLayout.tsx",
    "layouts/BannerBillLayout.tsx",
    "layouts/CornerstoreBillLayout.tsx",
    "BillContent.tsx",
];

describe("LazyBillSummaryMarkdown", () => {
    // @lat: [[admin-chunks-are-not-precached#Why the bill layouts do not import the markdown renderer directly]]
    beforeAll(async () => {
        await import("app/frontend/components/bill/BillSummaryMarkdown");
    });

    afterEach(cleanup);

    it("renders the summary once the markdown chunk resolves", async () => {
        render(<LazyBillSummaryMarkdown summary="Lets Baltimore create Conservation Districts." />);

        await waitFor(
            () => expect(screen.getByText("Lets Baltimore create Conservation Districts.")).toBeInTheDocument(),
            { timeout: 5000 },
        );
    });

    it("renders markdown structure as headings and lists", async () => {
        const { container } = render(
            <LazyBillSummaryMarkdown summary={"## Purpose\n\nA short explanation.\n\n- First item\n- Second item"} />,
        );

        await waitFor(() => {
            expect(container.querySelector("h2")?.textContent).toBe("Purpose");
            expect(container.querySelectorAll("ul > li")).toHaveLength(2);
        });
    });

    it("shows a placeholder of its own rather than suspending the whole layout", async () => {
        vi.resetModules();
        vi.doMock("app/frontend/components/bill/BillSummaryMarkdown", () => new Promise(() => {}));

        const { default: Pending } = await import("app/frontend/components/bill/layouts/LazyBillSummaryMarkdown");
        const { container } = render(<Pending summary="Anything at all." />);

        expect(container.textContent).not.toContain("Anything at all.");
        expect(container.querySelector(".break-words")).not.toBeNull();

        vi.doUnmock("app/frontend/components/bill/BillSummaryMarkdown");
        vi.resetModules();
    });

    it.each(SUMMARY_RENDERERS)("keeps the markdown renderer out of %s's static imports", (fileName) => {
        const source = readFileSync(resolve(BILL_DIR, fileName), "utf8");

        expect(source).toContain("LazyBillSummaryMarkdown");
        expect(source).not.toMatch(/^import\s+BillSummaryMarkdown\s+from/m);
    });
});
