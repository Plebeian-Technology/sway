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
}
export const formatDate = (datetime: string): string => {
    return new Date(datetime).toLocaleDateString("en-US");
}

export const formatDateTime = (datetime: string): string => {
    return new Date(datetime).toLocaleString("en-US");
}