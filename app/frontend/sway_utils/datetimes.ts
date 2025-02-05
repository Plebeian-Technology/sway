import { format, parseISO } from "date-fns";

export const getDateFromString = (date?: string) => {
    if (!date) {
        return new Date();
    } else {
        const d = new Date(date);
        // eslint-disable-next-line
        if (d.toString() == "Invalid Date") {
            return new Date();
        } else {
            return d;
        }
    }
};

export const formatDateISO = (datetime: string): string => {
    return new Date(datetime).toISOString();
};

export const formatDate = (datetime: string): string => {
    return format(parseISO(datetime), "MMMM dd, yyyy");
};
