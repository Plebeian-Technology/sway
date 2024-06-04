export const removeNonDigits = (string: string | null | undefined) => {
    if (typeof string === "string") {
        return string.replace(/\D/g, "");
    } else {
        return string || "";
    }
};

export const PHONE_INPUT_TRANSFORMER = {
    input: (value: string) => formatPhone(value),
    output: (e: React.ChangeEvent<any>) => removeNonDigits(e.target.value),
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

    // logDev("Formatting Phone -", {
    //     input,
    //     replaced,
    //     value,
    //     areaCode,
    //     middle,
    //     last,
    // });

    if (value.length > 6) {
        return `(${areaCode}) ${middle} - ${last}`;
    } else if (value.length > 3) {
        return `(${areaCode}) ${middle}`;
    } else if (value.length > 0) {
        return `(${areaCode}`;
    }
    return value;
};

/*
 * Because the google-libphonenumber pacakge size is huge (555kb)
 * do a simple phone validation on the front end
 * and save the real validation for the backend
 */
export const isValidPhoneNumber = (value: any, isRequired?: boolean): boolean => {
    if (!value || typeof value !== "string") {
        // logDev("isValidPhoneNumber - no value received. Return", !isRequired);
        return !isRequired;
    }

    try {
        const phone = removeNonDigits(value);
        if (!phone) {
            // logDev("isValidPhoneNumber - no phone received. Return", !isRequired);
            return !isRequired;
        }

        if (phone.length !== 10) {
            // logDev(
            //     `isValidPhoneNumber - phone is ${phone.length} digits. NOT 10 or 11. Return false`,
            // );
            return false;
        }

        // * Phone AREA CODE does NOT start with a 0 or 1 (no area-codes start with a 0 or 1)
        if (phone.length === 10 && (phone.startsWith("0") || phone.startsWith("1"))) {
            // logDev(
            //     `isValidPhoneNumber - ${phone.length} digit phone STARTS WITH 0 or 1. Return false.`,
            // );
            return false;
        }

        const match = !!phone.match(/\d{10}/); // NOSONAR
        // logDev("isValidPhoneNumber - phone pattern matches?. Return", match);
        return match;
    } catch (error) {
        // logDev("isValidPhoneNumber - Error validating phone number -", value);
        console.error("isValidPhoneNumber - Error validating phone number", error);
        return false;
    }
};
