import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { Button } from "@/components/ui/button";

// @lat: [[theme-tokens#Why density and motion belong to the theme]]
describe("Button icon sizes — responsive touch target", () => {
    it("size=icon is size-11 below sm and size-9 at sm and up", () => {
        render(<Button size="icon" aria-label="icon" />);
        const className = screen.getByRole("button").className;
        expect(className).toContain("size-11");
        expect(className).toContain("sm:size-9");
    });

    it("size=icon-sm is size-11 below sm and size-8 at sm and up", () => {
        render(<Button size="icon-sm" aria-label="icon-sm" />);
        const className = screen.getByRole("button").className;
        expect(className).toContain("size-11");
        expect(className).toContain("sm:size-8");
    });

    it("size=icon-lg is size-11 below sm and size-10 at sm and up", () => {
        render(<Button size="icon-lg" aria-label="icon-lg" />);
        const className = screen.getByRole("button").className;
        expect(className).toContain("size-11");
        expect(className).toContain("sm:size-10");
    });

    it("size=icon-xs stays fixed at size-6", () => {
        render(<Button size="icon-xs" aria-label="icon-xs" />);
        const className = screen.getByRole("button").className;
        expect(className).toContain("size-6");
        expect(className).not.toContain("size-11");
    });
});
