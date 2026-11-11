import { sway } from "sway";

export const isAtLargeLegislator = (district: sway.IDistrict | null) => district?.number === 0;

const districtMatches = (left?: sway.IDistrict, right?: sway.IDistrict | null) => {
    if (!left || !right) return false;

    if (left.name && right.name) {
        return left.name === right.name;
    }

    return left.number === right.number && left.region_code === right.region_code;
};

const getDistrictLegislators = (
    district?: sway.IDistrict,
    legislators: sway.ILegislator[] = [],
): sway.ILegislator[] => {
    const matches = legislators
        .filter((legislator) => districtMatches(district, legislator.district))
        .sort((left, right) => left.full_name.localeCompare(right.full_name));

    const activeMatches = matches.filter((legislator) => legislator.active);
    return activeMatches.length > 0 ? activeMatches : matches;
};

export const getDistrictLegislatorNames = (district?: sway.IDistrict, legislators: sway.ILegislator[] = []) =>
    getDistrictLegislators(district, legislators).map((legislator) => legislator.full_name);
