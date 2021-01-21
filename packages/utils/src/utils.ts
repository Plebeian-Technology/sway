/** @format */
/* eslint-disable */

export const IS_DEVELOPMENT = process.env.NODE_ENV === "development";
export const isNotProduction = process.env.NODE_ENV !== "production";
export const isProduction = process.env.NODE_ENV === "production";


const isEmptyObject = (obj: any) => {
    if (!obj) return true;

    if (typeof obj === "number" || typeof obj === "string") return false;

    if (Array.isArray(obj) && obj.length === 0) return true;

    for (const key in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, key)) return false;
    }
    return true;
};

export const isNumber = (value: any) =>
    typeof value === "number" && isFinite(value);

const flatten = (arrays: any[]): any[] => {
    return [].concat(...arrays);
};

const get = (object: any, path: string, value: any = null): any => {
    const pathArray = path.split(".").filter((key) => key);

    const pathArrayFlat = flatten(
        pathArray.map((part) =>
            typeof part === "string" ? part.split(".") : part,
        ),
    );

    return (
        pathArrayFlat.reduce(
            (obj: any, key: string) => obj && obj[key],
            object,
        ) || value
    );
};

const removeTimestamps = (firebaseItem: any) => {
    if (!firebaseItem) return firebaseItem;

    const { createdAt, updatedAt, ..._firebaseItem } = firebaseItem;
    return _firebaseItem;
};

const titleize = (string: string, separator = " ", joiner = " ") => {
    const words = string.split(separator);

    return words
        .map((word: string) => {
            return word[0].toUpperCase() + word.substring(1);
        })
        .join(joiner);
};

export {
    isEmptyObject,
    flatten,
    get,
    removeTimestamps,
    titleize,
};
