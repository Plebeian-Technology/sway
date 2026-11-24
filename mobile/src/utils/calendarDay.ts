// @lat: [[mobile-bill-creator#Sections#The schedule section]]
export const calendarDayToDate = (day: string): Date => {
    const [year, month, date] = day.split("-").map(Number);
    return new Date(year, month - 1, date);
};

export const dateToCalendarDay = (date: Date): string => {
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${date.getFullYear()}-${month}-${day}`;
};

export const parseCalendarDay = (text: string): Date | null => {
    const trimmed = text.trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return null;
    const date = calendarDayToDate(trimmed);
    return dateToCalendarDay(date) === trimmed ? date : null;
};

export const localToday = (): Date => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), now.getDate());
};
