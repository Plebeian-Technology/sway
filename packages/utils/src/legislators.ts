import { sway } from "sway";

export const isAtLargeLegislator = (
    legislator: sway.IBasicLegislator | sway.ILegislator,
) => {
    return legislator.district === `${legislator.regionCode.toUpperCase()}0`;
};

export const getNumericDistrict = (district: string): number | undefined => {
    const match = district.match(/\d+/);
    if (!match || !match[0]) return;

    return Number(match[0]);
};

export const getTextDistrict = (district: string): string | undefined => {
    const match = district.match(/[A-Z]+/);
    if (!match || !match[0]) return;

    return String(match[0]);
};
