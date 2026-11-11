import { describe, expect, it } from "vitest";

import { colourDeclarationsIn, namesAnUnreadableColour, notationOf, toHex, uniqueColourValue } from "./colourNotation";

/**
 // @lat: [[theme-test-suite-silent-failure-guards#Colour notation: one shared module for two gates that used to disagree]]
 */
describe("colour notation", () => {
    describe("toHex", () => {
        it("reads the two notations the themes are written in", () => {
            expect(toHex("#5fcf89")).toBe("#5fcf89");
            expect(toHex("rgb(95 207 137)")).toBe("#5fcf89");
            expect(toHex("rgb(95, 207, 137)")).toBe("#5fcf89");
        });

        it("pads a channel that is one digit in hex", () => {
            expect(toHex("rgb(1 2 3)")).toBe("#010203");
        });

        it("returns nothing for a notation it cannot convert", () => {
            expect(toHex("oklch(0.7 0.15 160)")).toBeNull();
            expect(toHex("#fff")).toBeNull();
            expect(toHex("1rem")).toBeNull();
        });
    });

    describe("notationOf", () => {
        it("names the notation so a failure can say which one it met", () => {
            expect(notationOf("#5fcf89")).toBe("6-digit hex");
            expect(notationOf("rgb(95 207 137)")).toBe("rgb()");
            expect(notationOf("oklch(0.7 0.15 160)")).toBe("oklch()");
            expect(notationOf("color-mix(in oklab, red, blue)")).toBe("color-mix()");
            expect(notationOf("#fff")).toBe("3-digit hex");
        });

        it("says nothing for a value that names no colour", () => {
            expect(notationOf("1rem")).toBeNull();
            expect(notationOf("var(--primary)")).toBeNull();
        });
    });

    describe("namesAnUnreadableColour", () => {
        it("is true for a colour written in a notation we cannot measure", () => {
            expect(namesAnUnreadableColour("oklch(0.7 0.15 160)")).toBe(true);
            expect(namesAnUnreadableColour("#fff")).toBe(true);
        });

        it("is false for the notations we read", () => {
            expect(namesAnUnreadableColour("#5fcf89")).toBe(false);
            expect(namesAnUnreadableColour("rgb(95 207 137)")).toBe(false);
        });

        // A scrim carries transparency, so there is no one surface to measure
        // it against. Recognised, and left alone on purpose.
        it("is false for rgba(), which is unmeasurable by design", () => {
            expect(namesAnUnreadableColour("rgba(0, 0, 0, 0.5)")).toBe(false);
        });

        it("is false for a value that is not a colour", () => {
            expect(namesAnUnreadableColour("1rem")).toBe(false);
        });
    });

    describe("colourDeclarationsIn", () => {
        it("keeps the value as written, so a caller can search built CSS for it", () => {
            const found = colourDeclarationsIn("--a: rgb(95 207 137); --b: 1rem; --c: #5fcf89;");

            expect(found).toEqual([
                { name: "--a", value: "rgb(95 207 137)", hex: "#5fcf89" },
                { name: "--c", value: "#5fcf89", hex: "#5fcf89" },
            ]);
        });
    });

    describe("uniqueColourValue", () => {
        it("returns a colour no other theme declares, as written", () => {
            expect(uniqueColourValue("a.css", "--x: #112233;", ["--y: #445566;"])).toBe("#112233");
        });

        // The point of converting before comparing: the same colour in two
        // notations is the same colour, and cannot key a theme.
        it("counts one colour written two ways as shared", () => {
            expect(() => uniqueColourValue("a.css", "--x: #5fcf89;", ["--y: rgb(95 207 137);"])).toThrow(
                /shares every one of its colours/,
            );
        });

        // The reason this issue exists. Same failure, different cause, and the
        // fixes are not the same — so the messages must not be either.
        it("names the notation when the theme is written in one it cannot read", () => {
            expect(() => uniqueColourValue("a.css", "--x: oklch(0.7 0.15 160);", ["--y: #445566;"])).toThrow(
                /cannot read.*--x: oklch\(0\.7 0\.15 160\) \(oklch\(\)\)/,
            );
        });

        it("does not blame the notation when a readable colour is merely shared", () => {
            expect(() => uniqueColourValue("a.css", "--x: #445566;", ["--y: #445566;"])).toThrow(
                /shares every one of its colours/,
            );
        });
    });
});
