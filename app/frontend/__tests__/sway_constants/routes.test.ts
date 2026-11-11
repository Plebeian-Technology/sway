import { describe, expect, it } from "vitest";
import { ROUTES } from "app/frontend/sway_constants/routes";

describe("ROUTES.legislator", () => {
    // config/routes.rb declares only `resources :legislators, only: [index, show]`,
    // which gives /legislators/:id, so this helper must build a path with that
    // one id segment and nothing more.
    it("emits /legislators/:id for the modern single-arg call", () => {
        expect(ROUTES.legislator(5)).toBe("/legislators/5");
        expect(ROUTES.legislator("42")).toBe("/legislators/42");
    });

    // Legacy 2-arg call: (swayLocaleSlug, id)
    it("ignores a leading locale arg when an id follows (legacy 2-arg call)", () => {
        expect(ROUTES.legislator("baltimore-maryland-united_states", "5")).toBe("/legislators/5");
        expect(ROUTES.legislator("congress-congress-united_states", 9)).toBe("/legislators/9");
    });

    it("falls back to the :id route pattern with no args", () => {
        expect(ROUTES.legislator()).toBe("/legislators/:id");
    });
});
