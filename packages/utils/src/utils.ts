/** @format */
/* eslint-disable */

export const IS_DEVELOPMENT = process.env.NODE_ENV === "development";
export const isNotProduction = process.env.NODE_ENV !== "production";
export const isProduction = process.env.NODE_ENV === "production";

export const isEmptyObject = (obj: any) => {
    if (!obj) return true;

    if (typeof obj === "number" || typeof obj === "string") return false;

    if (Array.isArray(obj) && obj.length === 0) return true;

    for (const key in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, key)) return false;
    }
    return true;
};

export const createNotificationDate = () => {
    const date = new Date();
    return date.toISOString().split("T")[0];
}

export const isNumber = (value: any) =>
    typeof value === "number" && isFinite(value);

export const flatten = (arrays: any[]): any[] => {
    return [].concat(...arrays);
};

export const isFirebaseUser = (user: any): boolean => {
    return user && (user.za || user.refreshToken)
}

export const withNumberSuffix = (n: number) => {
    const s = String(n);
    if (!s) return n;
    if (n <= 0) return n;
    if (s.endsWith("1") && n !== 11) return `${s}st`;
    if (s.endsWith("2") && n !== 12) return `${s}nd`;
    if (s.endsWith("3") && n !== 13) return `${s}rd`;
    return `${s}th`;
};

export const get = (object: any, path: string, value: any = null): any => {
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

export const removeTimestamps = (firebaseItem: any) => {
    if (!firebaseItem) return firebaseItem;

    const { createdAt, updatedAt, ..._firebaseItem } = firebaseItem;
    return _firebaseItem;
};

export const titleize = (string: string, separator = " ", joiner = " ") => {
    if (!string) return ""

    const words = string.toLowerCase().split(separator);

    return words
        .map((word: string) => {
            return word[0].toUpperCase() + word.substring(1);
        })
        .join(joiner);
};

export const formatPhone = (phone: string): string => {
    const _withoutSpecialCharacters = phone.replace(/\D/g, "");
    if (IS_DEVELOPMENT && _withoutSpecialCharacters.length !== 10) {
        console.error(
            "(dev) Phone without special characters is not 10 digits -",
            _withoutSpecialCharacters,
        );
    }
    return "+1 " + _withoutSpecialCharacters
        .split("")
        .map((char: string, index: number) => {
            if (index === 0) {
                return `(${char}`;
            }
            if (index === 2) {
                return `${char}) `;
            }
            if (index === 5) {
                return `${char}-`;
            }
            return char;
        })
        .join("");
}