import { sway } from "sway";

export const isAtLargeLegislator = (legislator: sway.IBasicLegislator | sway.ILegislator) => {
    return legislator.district === `${legislator.regionCode.toUpperCase()}0`;
};
