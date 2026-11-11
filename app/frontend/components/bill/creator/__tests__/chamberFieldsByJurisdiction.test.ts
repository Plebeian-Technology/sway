// @lat: [[jurisdiction-rules-design#bill_chambers: replacing a guess with a declaration]]

import { describe, expect, it } from "vitest";

import { BILL_INPUTS } from "app/frontend/components/bill/creator/inputs";
import type { sway } from "sway";

const locale = (overrides: Partial<sway.ISwayLocale> & Pick<sway.ISwayLocale, "bill_chambers">): sway.ISwayLocale =>
    ({
        id: 1,
        name: "test-test-united_states",
        city: "test",
        region_code: "MD",
        region_name: "test",
        country: "united_states",
        icon_url: "",
        time_zone: "Etc/UTC",
        current_session_start_date: "2024-12-05",
        default_bill_chamber: null,
        ...overrides,
    }) as sway.ISwayLocale;

const chamberDisabledFor = (l: sway.ISwayLocale) => Boolean(BILL_INPUTS.chamber.disableOn?.(l));
const senateDateDisabledFor = (l: sway.ISwayLocale) => Boolean(BILL_INPUTS.senate_vote_date_time_utc.disableOn?.(l));

describe("the chamber picker and the senate vote date", () => {
    it("switches both off for a place with one council", () => {
        const baltimore = locale({ city: "baltimore", region_name: "maryland", bill_chambers: ["council"] });

        expect(chamberDisabledFor(baltimore)).toBe(true);
        expect(senateDateDisabledFor(baltimore)).toBe(true);
    });

    it("leaves both on for a two-chamber legislature", () => {
        const maryland = locale({
            city: "maryland",
            region_name: "maryland",
            bill_chambers: ["house", "senate", "both"],
        });

        expect(chamberDisabledFor(maryland)).toBe(false);
        expect(senateDateDisabledFor(maryland)).toBe(false);
    });

    // The case the string comparison could never get right: a CITY whose
    // council sits alongside a senate. Its name differs from its region's, so
    // the old test switched both fields off.
    it("leaves both on for a city that has a senate", () => {
        const twoChamberCity = locale({
            city: "somewhere",
            region_name: "maryland",
            bill_chambers: ["council", "senate", "both"],
        });

        expect(chamberDisabledFor(twoChamberCity)).toBe(false);
        expect(senateDateDisabledFor(twoChamberCity)).toBe(false);
    });

    // Greying a field out is a claim about the place. Sway has none to make for
    // a jurisdiction nobody has declared, and registration creates those — one
    // for each reader's city and state — so the admin picks instead.
    it("leaves both on for a jurisdiction nobody has declared", () => {
        const undeclared = locale({ city: "chicago", region_name: "illinois", bill_chambers: null });

        expect(chamberDisabledFor(undeclared)).toBe(false);
        expect(senateDateDisabledFor(undeclared)).toBe(false);
    });

    // @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared bill chambers]]
    it("leaves both on, and throws nothing, when the field is missing entirely", () => {
        const stale = locale({ city: "baltimore", region_name: "maryland", bill_chambers: null });
        delete (stale as Partial<sway.ISwayLocale>).bill_chambers;

        expect(() => senateDateDisabledFor(stale)).not.toThrow();
        expect(chamberDisabledFor(stale)).toBe(false);
        expect(senateDateDisabledFor(stale)).toBe(false);
    });
});
