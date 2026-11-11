import { afterEach, describe, expect, it } from "vitest";

import {
    calendarDayToDate,
    dateToCalendarDay,
    formatCalendarDay,
    formatDate,
    formatDateShort,
    formatDateTime,
} from "app/frontend/sway_utils/datetimes";

const ORIGINAL_TZ = process.env.TZ;

afterEach(() => {
    process.env.TZ = ORIGINAL_TZ;
});

describe("calendarDayToDate", () => {
    // @lat: [[bill-schedule-calendar-dates#Why local midnight instead of formatting in UTC]]
    it("keeps the day the database holds, not the day before, in Eastern time", () => {
        const original = process.env.TZ;
        process.env.TZ = "America/New_York";
        try {
            const d = calendarDayToDate("2026-09-08");
            expect(d.getFullYear()).toBe(2026);
            expect(d.getMonth()).toBe(8);
            expect(d.getDate()).toBe(8);
        } finally {
            process.env.TZ = original;
        }
    });

    it("matches a calendar cell built the same way, for isSameDay-style comparisons", () => {
        const fromString = calendarDayToDate("2026-09-08");
        const fromClick = new Date(2026, 8, 8);
        expect(fromString.getTime()).toBe(fromClick.getTime());
    });
});

describe("dateToCalendarDay", () => {
    // @lat: [[bill-schedule-calendar-dates#Why a picked day travels as a bare day]]
    it.each(["Asia/Tokyo", "Pacific/Auckland", "America/New_York", "UTC"])(
        "names the day the operator clicked in %s, not the day the instant lands on",
        (tz) => {
            process.env.TZ = tz;

            expect(dateToCalendarDay(new Date(2026, 8, 8))).toBe("2026-09-08");
        },
    );

    it("is the inverse of calendarDayToDate east of UTC, where an instant would lose a day", () => {
        process.env.TZ = "Asia/Tokyo";

        const clicked = new Date(2026, 8, 8);

        expect(dateToCalendarDay(clicked)).toBe("2026-09-08");
        expect(calendarDayToDate(dateToCalendarDay(clicked)).getTime()).toBe(clicked.getTime());
        // @lat: [[bill-schedule-calendar-dates#Why a picked day travels as a bare day]]
        expect(clicked.toISOString().slice(0, 10)).toBe("2026-09-07");
    });

    it("pads single-digit months and days", () => {
        expect(dateToCalendarDay(new Date(2026, 0, 3))).toBe("2026-01-03");
    });
});

describe("formatDate, formatDateTime, and formatDateShort", () => {
    it("returns fallback strings for invalid date inputs without throwing RangeError", () => {
        expect(formatDate("not-a-date")).toBe("Invalid Date");
        expect(formatDateTime("not-a-date")).toBe("Invalid Date at Invalid Date");
        expect(formatDateShort("not-a-date")).toBe("Invalid Date");
    });

    it("invalidates cached Intl.DateTimeFormat instances when process.env.TZ changes", () => {
        const original = process.env.TZ;
        const iso = "2026-05-01T02:30:00Z";
        try {
            process.env.TZ = "UTC";
            const utcDate = formatDate(iso);
            const utcDateTime = formatDateTime(iso);
            const utcShort = formatDateShort(iso);

            process.env.TZ = "America/Los_Angeles";
            const laDate = formatDate(iso);
            const laDateTime = formatDateTime(iso);
            const laShort = formatDateShort(iso);

            expect(utcDate).toBe("May 01, 2026");
            expect(laDate).toBe("April 30, 2026");
            expect(utcDateTime).not.toBe(laDateTime);
            expect(utcShort).toBe("5/1/2026");
            expect(laShort).toBe("4/30/2026");
        } finally {
            process.env.TZ = original;
        }
    });

    it("formats bare YYYY-MM-DD calendar days without shifting to the prior day in Western timezones", () => {
        process.env.TZ = "America/New_York";
        expect(formatCalendarDay("2026-09-08")).toBe("September 08, 2026");
        expect(formatCalendarDay(null)).toBeNull();
        expect(formatCalendarDay("")).toBeNull();
        expect(formatCalendarDay("not-a-date")).toBeNull();
        expect(formatCalendarDay("2026-02-31")).toBeNull();
        expect(formatCalendarDay("2026-99-99")).toBeNull();
    });
});
