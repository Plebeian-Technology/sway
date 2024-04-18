import { isNumeric } from ".";

export const isAtLargeLegislator = ({
    district,
    regionCode,
}: {
    district: string;
    regionCode: string;
}) => {
    if (!district || !regionCode) return false;
    return district === "0" || district.toUpperCase() === `${regionCode.toUpperCase()}0`;
};

export const getNumericDistrict = (district: string): number | undefined => {
    const match = district.match(/\d+/);
    if (!match?.first()) return;

    return Number(match.first());
};

export const getTextDistrict = (district: string): string | undefined => {
    const match = district.match(/[A-Z]+/);
    if (!match?.first()) return;

    return String(match.first());
};

export const toFormattedNameFromExternalId = (externalId: string) => {
    const split = externalId.split("-");
    let string = "";
    for (const substring of split) {
        if (!isNumeric(substring)) {
            string += substring + " ";
        }
    }
    return string.trim();
};
