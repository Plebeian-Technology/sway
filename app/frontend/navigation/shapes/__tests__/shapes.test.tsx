import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { SHAPE_COMPONENTS } from "app/frontend/navigation/shapes";
import type { TShapeKey } from "app/frontend/navigation/placeholderRegistry";

const SHAPE_KEYS: TShapeKey[] = [
    "home",
    "list",
    "detail",
    "form",
    "document",
    "dashboard",
    "settings",
    "creator",
    "generic",
];

const FORBIDDEN_CLASS_TOKENS = [
    "bg-" + "primary",
    "bg-" + "accent",
    "bg-" + "destructive",
    "shadow" + "-",
    "scale" + "-",
    "translate" + "-",
    "animate-" + "bounce",
    "animate-" + "spin",
    "animate-" + "ping",
];

const carriesForbiddenClass = (className: string): boolean =>
    FORBIDDEN_CLASS_TOKENS.some((token) => className.includes(token));

describe.each(SHAPE_KEYS)("%s shape", (key) => {
    it("renders no text content", () => {
        const Shape = SHAPE_COMPONENTS[key];
        const { container } = render(<Shape />);
        expect(container.textContent).toBe("");
    });

    it("marks every placeholder-block element aria-hidden", () => {
        const Shape = SHAPE_COMPONENTS[key];
        const { container } = render(<Shape />);
        const blocks = container.querySelectorAll(".placeholder-block");
        const hidden = container.querySelectorAll(".placeholder-block[aria-hidden='true']");
        expect(blocks.length).toBeGreaterThan(1);
        expect(hidden.length).toBe(blocks.length);
    });

    it("carries no accent, shadow, scale, translate or attention-seeking animation class", () => {
        const Shape = SHAPE_COMPONENTS[key];
        const { container } = render(<Shape />);
        const offenders = Array.from(container.querySelectorAll("*")).filter((el) =>
            carriesForbiddenClass(el.className.toString()),
        );
        expect(offenders).toEqual([]);
    });
});

describe("SHAPE_COMPONENTS", () => {
    it("has exactly one entry per shape key", () => {
        expect(Object.keys(SHAPE_COMPONENTS).sort()).toEqual([...SHAPE_KEYS].sort());
    });
});
