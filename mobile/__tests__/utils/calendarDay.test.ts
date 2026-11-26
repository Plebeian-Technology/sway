import { calendarDayToDate, dateToCalendarDay, parseCalendarDay } from "../../src/utils/calendarDay";

// @lat: [[mobile-bill-creator#Sections#The schedule section]]
describe("calendarDay", () => {
    it("reads and writes a bare day at local midnight", () => {
        const date = calendarDayToDate("2026-09-08");

        expect([date.getFullYear(), date.getMonth(), date.getDate(), date.getHours()]).toEqual([2026, 8, 8, 0]);
        expect(dateToCalendarDay(date)).toBe("2026-09-08");
    });

    it("rejects text that is not a real day", () => {
        expect(parseCalendarDay("2026-02-31")).toBeNull();
        expect(parseCalendarDay("2026-9-8")).toBeNull();
        expect(parseCalendarDay("soon")).toBeNull();
        expect(parseCalendarDay(" 2026-09-08 ")?.getDate()).toBe(8);
    });
});
