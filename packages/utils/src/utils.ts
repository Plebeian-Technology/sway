/** @format */
/* eslint-disable */

const _get = require("lodash.get");

declare global {
    interface Array<T> {
        first(): T;
        last(): T;
    }
}

if (!Array.prototype.first) {
    Array.prototype.first = function (defaultValue?: any) {
        return this[0] || defaultValue;
    };
}

if (!Array.prototype.last) {
    Array.prototype.last = function (defaultValue?: any) {
        return this[this.length - 1] || defaultValue;
    };
}

export const get = _get;

export const IS_DEVELOPMENT = process.env.NODE_ENV === "development";
export const IS_NOT_PRODUCTION = process.env.NODE_ENV !== "production";
export const IS_PRODUCTION = process.env.NODE_ENV === "production";

export const logDev = (...args: any[]) => {
    if (IS_NOT_PRODUCTION) {
        const [message, ...extra] = args;
        if (typeof message === "string") {
            console.log(`(dev) ${message}`, ...extra);
        } else {
            console.log("(dev)", message, ...extra);
        }
    }
};

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
};

export const isNumber = (value: any) => typeof value === "number" && isFinite(value);

export const isNumeric = (string: string | null | undefined): boolean => {
    if (!string) return false;

    if (typeof string === "number") {
        return true;
    }

    if (typeof string !== "string") {
        return false;
    }

    return string.match(/\d+/) !== null;
};

export const flatten = (arrays: any[]): any[] => {
    return [].concat(...arrays);
};

export const isFirebaseUser = (user: any): boolean => {
    return user && (user.za || user.refreshToken);
};

export const withNumberSuffix = (n: number) => {
    const s = String(n);
    if (!s) return n;
    if (n <= 0) return n;
    if (s.endsWith("1") && n !== 11) return `${s}st`;
    if (s.endsWith("2") && n !== 12) return `${s}nd`;
    if (s.endsWith("3") && n !== 13) return `${s}rd`;
    return `${s}th`;
};

export const removeTimestamps = (firebaseItem: any) => {
    if (!firebaseItem) return firebaseItem;

    const { createdAt, updatedAt, ..._firebaseItem } = firebaseItem;
    return _firebaseItem;
};

export const titleize = (string: string, separator = " ", joiner = " ") => {
    if (!string) return "";

    const words = string.toLowerCase().split(separator);

    const toJoin = [];
    for (const word of words) {
        if (word) {
            toJoin.push(word[0].toUpperCase() + word.substring(1));
        }
    }
    return toJoin.join(joiner);
};

export const formatPhone = (phone: string): string => {
    const _withoutSpecialCharacters = phone.replace(/\D/g, "");
    if (_withoutSpecialCharacters.length !== 10) {
        console.error(
            "Phone without special characters is not 10 digits -",
            _withoutSpecialCharacters,
        );
    }
    return (
        "+1 " +
        _withoutSpecialCharacters
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
            .join("")
    );
};
