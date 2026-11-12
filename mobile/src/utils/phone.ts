// @lat: [[mobile-web-parity-utils#mobile/src/utils/phone.ts: matching the web's phone formatting]]

export const removeNonDigits = (value: string | null | undefined): string => {
    if (typeof value === "string") {
        return value.replace(/\D/g, "");
    }
    return value || "";
};

export const formatPhone = (input: string | null | undefined): string => {
    if (!input) return "";
    const digits = removeNonDigits(input);
    if (!digits) return "";

    const value = digits.substring(digits.length - 10, digits.length);
    const areaCode = value.substring(0, 3);
    const middle = value.substring(3, 6);
    const last = value.substring(6, 10);

    if (value.length > 6) return `(${areaCode}) ${middle} - ${last}`;
    if (value.length > 3) return `(${areaCode}) ${middle}`;
    if (value.length > 0) return `(${areaCode}`;
    return value;
};

// @lat: [[mobile-web-parity-utils#mobile/src/utils/phone.ts: matching the web's phone formatting]]
export const PHONE_INPUT_TRANSFORMER = {
    input: (value: string): string => {
        const v = removeNonDigits(value);
        if (v.length === 11 && v.startsWith("1")) return formatPhone(v.slice(1));
        return formatPhone(v);
    },
    output: (text: string): string => {
        const p = removeNonDigits(text);
        if (p.length === 11 && p.startsWith("1")) return p.slice(1);
        if (p.length > 10) return p.slice(0, 10);
        return p;
    },
};
