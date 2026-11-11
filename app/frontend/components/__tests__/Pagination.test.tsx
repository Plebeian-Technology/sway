import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import Pagination from "app/frontend/components/Pagination";

describe("Pagination", () => {
    afterEach(() => cleanup());

    it("renders nothing for a single-page collection", () => {
        const { container } = render(
            <Pagination page={1} pageCount={1} onPageChange={vi.fn<(page: number) => void>()} />,
        );
        expect(container).toBeEmptyDOMElement();
    });

    it("renders nothing when there are no pages at all", () => {
        const { container } = render(
            <Pagination page={1} pageCount={0} onPageChange={vi.fn<(page: number) => void>()} />,
        );
        expect(container).toBeEmptyDOMElement();
    });

    it("labels the control strip as a Pagination landmark", () => {
        render(<Pagination page={1} pageCount={3} onPageChange={vi.fn<(page: number) => void>()} />);
        expect(screen.getByRole("navigation", { name: "Pagination" })).toBeDefined();
    });

    it("renders one button per page, numbered", () => {
        render(<Pagination page={1} pageCount={3} onPageChange={vi.fn<(page: number) => void>()} />);
        expect(screen.getByRole("button", { name: "Page 1" })).toBeDefined();
        expect(screen.getByRole("button", { name: "Page 2" })).toBeDefined();
        expect(screen.getByRole("button", { name: "Page 3" })).toBeDefined();
    });

    it("marks the current page with aria-current=page and no other page", () => {
        render(<Pagination page={2} pageCount={3} onPageChange={vi.fn<(page: number) => void>()} />);
        expect(screen.getByRole("button", { name: "Page 2" }).getAttribute("aria-current")).toBe("page");
        expect(screen.getByRole("button", { name: "Page 1" }).getAttribute("aria-current")).toBeNull();
        expect(screen.getByRole("button", { name: "Page 3" }).getAttribute("aria-current")).toBeNull();
    });

    it("clicking a page number reports that page", async () => {
        const user = userEvent.setup();
        const onPageChange = vi.fn<(page: number) => void>();
        render(<Pagination page={1} pageCount={3} onPageChange={onPageChange} />);
        await user.click(screen.getByRole("button", { name: "Page 3" }));
        expect(onPageChange).toHaveBeenCalledWith(3);
    });

    it("Previous is disabled on the first page, enabled otherwise", () => {
        const { rerender } = render(
            <Pagination page={1} pageCount={3} onPageChange={vi.fn<(page: number) => void>()} />,
        );
        expect(screen.getByRole("button", { name: "Previous page" }).hasAttribute("disabled")).toBe(true);

        rerender(<Pagination page={2} pageCount={3} onPageChange={vi.fn<(page: number) => void>()} />);
        expect(screen.getByRole("button", { name: "Previous page" }).hasAttribute("disabled")).toBe(false);
    });

    it("Next is disabled on the last page, enabled otherwise", () => {
        const { rerender } = render(
            <Pagination page={3} pageCount={3} onPageChange={vi.fn<(page: number) => void>()} />,
        );
        expect(screen.getByRole("button", { name: "Next page" }).hasAttribute("disabled")).toBe(true);

        rerender(<Pagination page={2} pageCount={3} onPageChange={vi.fn<(page: number) => void>()} />);
        expect(screen.getByRole("button", { name: "Next page" }).hasAttribute("disabled")).toBe(false);
    });

    it("clicking Previous/Next reports the adjacent page", async () => {
        const user = userEvent.setup();
        const onPageChange = vi.fn<(page: number) => void>();
        render(<Pagination page={2} pageCount={3} onPageChange={onPageChange} />);

        await user.click(screen.getByRole("button", { name: "Previous page" }));
        expect(onPageChange).toHaveBeenCalledWith(1);

        await user.click(screen.getByRole("button", { name: "Next page" }));
        expect(onPageChange).toHaveBeenCalledWith(3);
    });
});

describe("Pagination windowing", () => {
    afterEach(() => cleanup());

    it("renders every page with no ellipsis when pageCount is small enough to fit", () => {
        render(<Pagination page={1} pageCount={7} onPageChange={vi.fn<(page: number) => void>()} />);
        for (let n = 1; n <= 7; n++) {
            expect(screen.getByRole("button", { name: `Page ${n}` })).toBeDefined();
        }
        expect(screen.queryByText("…")).toBeNull();
    });

    it("switches to windowing once pageCount exceeds the no-ellipsis threshold", () => {
        render(<Pagination page={1} pageCount={8} onPageChange={vi.fn<(page: number) => void>()} />);
        expect(screen.getByText("…")).toBeDefined();
    });

    it("shows only a right ellipsis when the current page is near the start", () => {
        render(<Pagination page={1} pageCount={38} onPageChange={vi.fn<(page: number) => void>()} />);
        expect(screen.getAllByText("…").length).toBe(1);
        expect(screen.getByRole("button", { name: "Page 1" })).toBeDefined();
        expect(screen.getByRole("button", { name: "Page 38" })).toBeDefined();
    });

    it("shows both ellipses when the current page is in the middle", () => {
        render(<Pagination page={19} pageCount={38} onPageChange={vi.fn<(page: number) => void>()} />);
        expect(screen.getAllByText("…").length).toBe(2);
        expect(screen.getByRole("button", { name: "Page 1" })).toBeDefined();
        expect(screen.getByRole("button", { name: "Page 19" })).toBeDefined();
        expect(screen.getByRole("button", { name: "Page 38" })).toBeDefined();
    });

    it("shows only a left ellipsis when the current page is near the end", () => {
        render(<Pagination page={38} pageCount={38} onPageChange={vi.fn<(page: number) => void>()} />);
        expect(screen.getAllByText("…").length).toBe(1);
        expect(screen.getByRole("button", { name: "Page 1" })).toBeDefined();
        expect(screen.getByRole("button", { name: "Page 38" })).toBeDefined();
    });

    it("keeps the first page, the last page, and the current page reachable at every position", () => {
        const pageCount = 38;
        for (const page of [1, 5, 19, 34, 38]) {
            const { unmount } = render(
                <Pagination page={page} pageCount={pageCount} onPageChange={vi.fn<(page: number) => void>()} />,
            );
            expect(screen.getByRole("button", { name: "Page 1" })).toBeDefined();
            expect(screen.getByRole("button", { name: `Page ${pageCount}` })).toBeDefined();
            expect(screen.getByRole("button", { name: `Page ${page}` }).getAttribute("aria-current")).toBe("page");
            unmount();
        }
    });

    it("renders the ellipsis as a non-interactive, aria-hidden marker, not a page", () => {
        render(<Pagination page={19} pageCount={38} onPageChange={vi.fn<(page: number) => void>()} />);
        const markers = screen.getAllByText("…");
        expect(markers.length).toBe(2);
        for (const marker of markers) {
            expect(marker.getAttribute("aria-hidden")).toBe("true");
            expect(marker.tagName.toLowerCase()).not.toBe("button");
        }
        expect(screen.queryByRole("button", { name: "…" })).toBeNull();
    });

    it("does not grow the number of rendered page buttons as pageCount grows past the windowing threshold", () => {
        const countPageButtons = (pageCount: number) => {
            const page = Math.ceil(pageCount / 2);
            const { unmount } = render(
                <Pagination page={page} pageCount={pageCount} onPageChange={vi.fn<(page: number) => void>()} />,
            );
            const count = screen.getAllByRole("button", { name: /^Page \d+$/ }).length;
            unmount();
            return count;
        };

        // @lat: [[pagination#Client-side pagination#Windowing the page strip]]
        const atUnscheduledBillsScale = countPageButtons(38);
        const atTenTimesThatScale = countPageButtons(500);

        expect(atUnscheduledBillsScale).toBe(atTenTimesThatScale);
        expect(atTenTimesThatScale).toBeLessThanOrEqual(6);
    });
});
