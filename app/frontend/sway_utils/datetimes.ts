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