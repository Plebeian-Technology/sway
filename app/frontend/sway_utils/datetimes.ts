interface IDateFormatters {
    tzKey: string;
    longDate: Intl.DateTimeFormat;
    time: Intl.DateTimeFormat;
    shortDate: Intl.DateTimeFormat;
}

let cachedFormatters: IDateFormatters | null = null;

const getFormatters = (): IDateFormatters => {
    const tzKey = typeof process !== "undefined" && process.env ? (process.env.TZ ?? "") : "";
    if (!cachedFormatters || cachedFormatters.tzKey !== tzKey) {
        cachedFormatters = {
            tzKey,
            longDate: new Intl.DateTimeFormat("en-US", { month: "long", day: "2-digit", year: "numeric" }),
            time: new Intl.DateTimeFormat("en-US", { hour: "2-digit", minute: "2-digit", hour12: true }),
            shortDate: new Intl.DateTimeFormat("en-US"),
        };
    }
    return cachedFormatters;
};

// @lat: [[bill-schedule-calendar-dates#Why local midnight instead of formatting in UTC]]
export const calendarDayToDate = (day: string): Date => {
    const [year, month, date] = day.split("-").map(Number);
    return new Date(year, month - 1, date);
};

// @lat: [[bill-schedule-calendar-dates#Why a picked day travels as a bare day]]
export const dateToCalendarDay = (date: Date): string => {
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${date.getFullYear()}-${month}-${day}`;
};

export const isValidDate = (d: Date): boolean => {
    return !isNaN(d.getTime());
};

export const formatDate = (datetime: string | Date): string => {
    const d = datetime instanceof Date ? datetime : new Date(datetime);
    if (!isValidDate(d)) return "Invalid Date";
    return getFormatters().longDate.format(d);
};

export const formatDateTime = (datetime: string | Date): string => {
    const d = datetime instanceof Date ? datetime : new Date(datetime);
    if (!isValidDate(d)) return "Invalid Date at Invalid Date";
    const formatters = getFormatters();
    return `${formatters.longDate.format(d)} at ${formatters.time.format(d)}`;
};

export const formatDateShort = (iso: string | null | undefined): string => {
    if (!iso) return "";
    const d = new Date(iso);
    if (!isValidDate(d)) return "Invalid Date";
    return getFormatters().shortDate.format(d);
};

// @lat: [[bill-schedule-calendar-dates#Why local midnight instead of formatting in UTC]]
export const formatCalendarDay = (day: string | null | undefined): string | null => {
    if (!day) return null;
    const trimmed = day.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
        const localDate = calendarDayToDate(trimmed);
        if (!isValidDate(localDate) || dateToCalendarDay(localDate) !== trimmed) return null;
        return formatDate(localDate);
    }
    const parsedDate = new Date(trimmed);
    if (!isValidDate(parsedDate)) return null;
    return formatDate(parsedDate);
};

export function relativeTime(isoString: string): string {
    const diff = Date.now() - new Date(isoString).getTime();
    const seconds = Math.floor(diff / 1000);
    // @lat: [[activity-log-stream#Why relativeTime clamps future timestamps to just now]]
    if (seconds < 0) return "just now";
    if (seconds < 60) return `${seconds}s ago`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
}
