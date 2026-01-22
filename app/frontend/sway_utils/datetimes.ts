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
    const d = new Date(datetime);
    return d.toLocaleDateString("en-US", { month: "long", day: "2-digit", year: "numeric" });
};

export const formatDateTime = (datetime: string): string => {
    const d = new Date(datetime);
    const datePart = d.toLocaleDateString("en-US", { month: "long", day: "2-digit", year: "numeric" });
    const timePart = d.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: true });
    return `${datePart} at ${timePart}`;
};

export const isValidDate = (d: Date): boolean => {
    return !isNaN(d.getTime());
};
