import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { exactTime, failureAge, failureTiming } from "app/frontend/sway_utils/failureTiming";

const NOW = new Date("2026-08-19T15:26:14.000Z");
const TWELVE_MINUTES_AGO = "2026-08-19T15:14:14.000Z"; // 12 minutes before NOW

const EXPECTED_EXACT_TIME = (() => {
    const d = new Date(TWELVE_MINUTES_AGO);
    const datePart = d.toLocaleDateString("en-US", { month: "long", day: "2-digit", year: "numeric" });
    const timePart = d.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: true });
    return `${datePart} at ${timePart}`;
})();

beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
});

afterEach(() => {
    vi.useRealTimers();
});

describe("failureAge", () => {
    it("returns the age for a good value", () => {
        expect(failureAge(TWELVE_MINUTES_AGO)).toEqual("12m ago");
    });

    it("returns null for null", () => {
        expect(failureAge(null)).toBeNull();
    });

    it("returns null for undefined", () => {
        expect(failureAge(undefined)).toBeNull();
    });

    it("returns null for the empty string", () => {
        expect(failureAge("")).toBeNull();
    });

    it("returns null for a whitespace string", () => {
        expect(failureAge("   ")).toBeNull();
    });

    it("returns null for an unreadable string", () => {
        expect(failureAge("not-a-date")).toBeNull();
    });
});

describe("exactTime", () => {
    it("returns the exact time for a good value", () => {
        expect(exactTime(TWELVE_MINUTES_AGO)).toEqual(EXPECTED_EXACT_TIME);
    });

    it("returns null for null", () => {
        expect(exactTime(null)).toBeNull();
    });

    it("returns null for undefined", () => {
        expect(exactTime(undefined)).toBeNull();
    });

    it("returns null for the empty string", () => {
        expect(exactTime("")).toBeNull();
    });

    it("returns null for a whitespace string", () => {
        expect(exactTime("   ")).toBeNull();
    });

    it("returns null for an unreadable string", () => {
        expect(exactTime("not-a-date")).toBeNull();
    });
});

describe("failureTiming", () => {
    it("returns the exact composed string for a fixed instant, including the separator", () => {
        expect(failureTiming(TWELVE_MINUTES_AGO)).toEqual(`Failed 12m ago — ${EXPECTED_EXACT_TIME}`);
    });

    it("returns null for null", () => {
        expect(failureTiming(null)).toBeNull();
    });

    it("returns null for undefined", () => {
        expect(failureTiming(undefined)).toBeNull();
    });

    it("returns null for the empty string", () => {
        expect(failureTiming("")).toBeNull();
    });

    it("returns null for a whitespace string", () => {
        expect(failureTiming("   ")).toBeNull();
    });

    it("returns null for an unreadable string", () => {
        expect(failureTiming("not-a-date")).toBeNull();
    });
});
