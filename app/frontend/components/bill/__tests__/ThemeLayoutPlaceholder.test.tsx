import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import ThemeLayoutPlaceholder from "app/frontend/components/bill/ThemeLayoutPlaceholder";

afterEach(() => {
    cleanup();
});

describe("ThemeLayoutPlaceholder", () => {
    it("renders a status region", () => {
        render(<ThemeLayoutPlaceholder />);

        expect(screen.getByRole("status")).toBeInTheDocument();
    });

    it("is built from the placeholder-block utility", () => {
        const { container } = render(<ThemeLayoutPlaceholder />);

        expect(container.querySelectorAll(".placeholder-block").length).toBeGreaterThan(0);
    });

    it("defaults to the detail shape", () => {
        const { container } = render(<ThemeLayoutPlaceholder />);

        expect(container.querySelectorAll(".placeholder-block").length).toBe(8);
    });

    it("renders the list shape's rows when asked for the list shape", () => {
        const { container } = render(<ThemeLayoutPlaceholder shape="list" />);

        expect(container.querySelectorAll(".placeholder-block").length).toBe(10);
    });

    it("passes a caller-provided className onto the status region", () => {
        render(<ThemeLayoutPlaceholder className="min-h-[600px]" />);

        expect(screen.getByRole("status")).toHaveClass("min-h-[600px]");
    });
});
