import { describe, expect, it } from "vitest";

import { countNoun } from "app/frontend/sway_utils/countNoun";

describe("countNoun", () => {
    it("uses the singular form at exactly one", () => {
        expect(countNoun(1, "letter", "letters")).toEqual("1 letter");
    });

    it("uses the plural form at zero", () => {
        expect(countNoun(0, "letter", "letters")).toEqual("0 letters");
    });

    it("uses the plural form at two", () => {
        expect(countNoun(2, "letter", "letters")).toEqual("2 letters");
    });

    it("formats the count with locale thousands separators", () => {
        expect(countNoun(1037523, "letter", "letters")).toEqual("1,037,523 letters");
    });
});
