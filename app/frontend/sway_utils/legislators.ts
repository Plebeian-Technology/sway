import { sway } from "sway";
import { isNumeric } from ".";

export const isAtLargeLegislator = (district: sway.IDistrict) => district?.number === 0;

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

export const toFormattedNameFromExternalId = (external_id: string) => {
    const split = external_id.split("-");
    let string = "";
    for (const substring of split) {
        if (!isNumeric(substring)) {
            string += substring + " ";
        }
    }
    return string.trim();
};
