export const isEmptyObject = (obj: any) => {
    if (!obj) return true;

    for (let key in obj) {
        if (obj.hasOwnProperty(key)) return false;
    }
    return true;
};
