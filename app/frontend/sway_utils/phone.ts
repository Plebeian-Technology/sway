export const removeNonDigits = (string: string | null | undefined) => {
    if (typeof string === "string") {
        return string.replace(/\D/g, "");
    } else {
        return string || "";
    }
};

export const PHONE_INPUT_TRANSFORMER = {
    input: (value: string) => {
        const v = removeNonDigits(value);
        if (v.length === 11 && v.startsWith("1")) {
            return formatPhone(v.slice(1));
        } else {
            return formatPhone(v);
        }
    },
    output: (e: React.ChangeEvent<any>) => {
        const p = removeNonDigits(e.target.value);
        if (p.length === 11 && p.startsWith("1")) {
            return p.slice(1);
        } else {
            return p;
        }
    },
};

export const formatPhone = (input: string[] | string | number | undefined | null): any => {
    if (!input) return "";

    const joined = Array.isArray(input) ? input.join("") : String(input);
    if (typeof joined !== "string") return input;

    const replaced = removeNonDigits(joined);
    if (!replaced) return "";

    const value = replaced.substring(replaced.length - 10, replaced.length);

    const areaCode = value.substring(0, 3);
    const middle = value.substring(3, 6);
    const last = value.substring(6, 10);

    if (value.length > 6) {
        return `(${areaCode}) ${middle} - ${last}`;
    } else if (value.length > 3) {
        return `(${areaCode}) ${middle}`;
    } else if (value.length > 0) {
        return `(${areaCode}`;
    }
    return value;
};
