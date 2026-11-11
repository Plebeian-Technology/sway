// @lat: [[term-window-design#Why formatTermWindow (app/frontend/sway_utils/termWindow.ts) prefers the real day]]

export interface ITermWindow {
    term_start_year?: number | null;
    term_end_year?: number | null;
    began_on?: string | null;
    ended_on?: string | null;
}

// @lat: [[bill-schedule-calendar-dates#Why local midnight instead of formatting in UTC]]
const formatDay = (iso: string): string =>
    new Date(iso).toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        timeZone: "UTC",
    });

const endpoint = (day: string | null | undefined, year: number | null | undefined): string | null => {
    if (day) return formatDay(day);
    return typeof year === "number" ? String(year) : null;
};

// @lat: [[term-window-design#Why formatTermWindow (app/frontend/sway_utils/termWindow.ts) prefers the real day]]
export const formatTermWindow = (term: ITermWindow | null | undefined): string | null => {
    if (!term) return null;

    const start = endpoint(term.began_on, term.term_start_year);
    const end = endpoint(term.ended_on, term.term_end_year);
    if (start === null || end === null) return null;

    return `${start}–${end}`;
};
