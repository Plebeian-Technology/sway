// Purely presentational — BillCreatorPicker owns sortMode; this component only renders
// the two halves and reports clicks via onSortModeChange.

import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import BillPickerSortToggle from "app/frontend/components/admin/creator/BillPickerSortToggle";

describe("BillPickerSortToggle", () => {
    it("renders the container and all segments", () => {
        render(<BillPickerSortToggle sortMode="newest" onSortModeChange={vi.fn<(mode: string) => void>()} />);

        expect(screen.getByTestId("bill-picker-sort-toggle")).toBeTruthy();
        expect(screen.getByTestId("sort-newest")).toBeTruthy();
        expect(screen.getByTestId("sort-alpha")).toBeTruthy();
        expect(screen.getByTestId("sort-score")).toBeTruthy();
        expect(screen.getByTestId("sort-latest-action")).toBeTruthy();
        expect(screen.getByText("Newest")).toBeTruthy();
        expect(screen.getByText("A-Z")).toBeTruthy();
        expect(screen.getByText("Most Interesting")).toBeTruthy();
        expect(screen.getByText("Recent intro/vote")).toBeTruthy();
    });

    it("marks the newest segment aria-pressed when sortMode is newest (default)", () => {
        render(<BillPickerSortToggle sortMode="newest" onSortModeChange={vi.fn<(mode: string) => void>()} />);

        expect(screen.getByTestId("sort-newest").getAttribute("aria-pressed")).toBe("true");
        expect(screen.getByTestId("sort-alpha").getAttribute("aria-pressed")).toBe("false");
        expect(screen.getByTestId("sort-score").getAttribute("aria-pressed")).toBe("false");
    });

    it("marks the alpha segment aria-pressed when sortMode is alpha", () => {
        render(<BillPickerSortToggle sortMode="alpha" onSortModeChange={vi.fn<(mode: string) => void>()} />);

        expect(screen.getByTestId("sort-newest").getAttribute("aria-pressed")).toBe("false");
        expect(screen.getByTestId("sort-alpha").getAttribute("aria-pressed")).toBe("true");
        expect(screen.getByTestId("sort-score").getAttribute("aria-pressed")).toBe("false");
    });

    it("marks the score segment aria-pressed when sortMode is score", () => {
        render(<BillPickerSortToggle sortMode="score" onSortModeChange={vi.fn<(mode: string) => void>()} />);

        expect(screen.getByTestId("sort-newest").getAttribute("aria-pressed")).toBe("false");
        expect(screen.getByTestId("sort-alpha").getAttribute("aria-pressed")).toBe("false");
        expect(screen.getByTestId("sort-score").getAttribute("aria-pressed")).toBe("true");
    });

    it("calls onSortModeChange('score') when the Most Interesting segment is clicked", () => {
        const onSortModeChange = vi.fn<(mode: string) => void>();
        render(<BillPickerSortToggle sortMode="newest" onSortModeChange={onSortModeChange} />);

        fireEvent.click(screen.getByTestId("sort-score"));

        expect(onSortModeChange).toHaveBeenCalledTimes(1);
        expect(onSortModeChange).toHaveBeenCalledWith("score");
    });

    it("calls onSortModeChange('newest') when the Newest segment is clicked", () => {
        const onSortModeChange = vi.fn<(mode: string) => void>();
        render(<BillPickerSortToggle sortMode="score" onSortModeChange={onSortModeChange} />);

        fireEvent.click(screen.getByTestId("sort-newest"));

        expect(onSortModeChange).toHaveBeenCalledTimes(1);
        expect(onSortModeChange).toHaveBeenCalledWith("newest");
    });

    it("calls onSortModeChange('alpha') when the A-Z segment is clicked", () => {
        const onSortModeChange = vi.fn<(mode: string) => void>();
        render(<BillPickerSortToggle sortMode="newest" onSortModeChange={onSortModeChange} />);

        fireEvent.click(screen.getByTestId("sort-alpha"));

        expect(onSortModeChange).toHaveBeenCalledTimes(1);
        expect(onSortModeChange).toHaveBeenCalledWith("alpha");
    });

    it("calls onSortModeChange('latest_action') when Recent intro/vote is clicked", () => {
        const onSortModeChange = vi.fn<(mode: string) => void>();
        render(<BillPickerSortToggle sortMode="newest" onSortModeChange={onSortModeChange} />);

        fireEvent.click(screen.getByTestId("sort-latest-action"));

        expect(onSortModeChange).toHaveBeenCalledTimes(1);
        expect(onSortModeChange).toHaveBeenCalledWith("latest_action");
    });

    it("buttons are type=button (never submit a surrounding form)", () => {
        render(<BillPickerSortToggle sortMode="newest" onSortModeChange={vi.fn<(mode: string) => void>()} />);

        expect(screen.getByTestId("sort-newest").getAttribute("type")).toBe("button");
        expect(screen.getByTestId("sort-alpha").getAttribute("type")).toBe("button");
        expect(screen.getByTestId("sort-score").getAttribute("type")).toBe("button");
        expect(screen.getByTestId("sort-latest-action").getAttribute("type")).toBe("button");
    });

    it("never applies select-none (labels must stay selectable/copyable)", () => {
        const { container } = render(
            <BillPickerSortToggle sortMode="newest" onSortModeChange={vi.fn<(mode: string) => void>()} />,
        );

        expect(container.innerHTML).not.toContain("select-none");
    });
});
