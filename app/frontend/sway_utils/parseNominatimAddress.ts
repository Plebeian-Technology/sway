import type { sway } from "sway";

export type TParsedNominatimAddress = Partial<sway.IAddress> & {
    region?: string;
    region_code?: string;
    latitude?: number;
    longitude?: number;
};

export interface INominatimAddress {
    house_number?: string | number;
    road?: string;
    street?: string;
    pedestrian?: string;
    footway?: string;
    cycleway?: string;
    path?: string;
    square?: string;
    city?: string;
    town?: string;
    village?: string;
    municipality?: string;
    hamlet?: string;
    borough?: string;
    suburb?: string;
    city_district?: string;
    quarter?: string;
    neighbourhood?: string;
    neighborhood?: string;
    county?: string;
    state?: string;
    region?: string;
    state_district?: string;
    state_code?: string;
    postcode?: string | number;
    country?: string;
    country_code?: string;
    "ISO3166-2-lvl4"?: string;
    [key: string]: unknown;
}

export interface INominatimPlace {
    place_id?: number | string;
    osm_type?: string;
    osm_id?: number | string;
    lat?: string | number;
    lon?: string | number;
    display_name?: string;
    class?: string;
    category?: string;
    type?: string;
    importance?: number;
    icon?: string;
    licence?: string;
    boundingbox?: string[];
    address?: INominatimAddress;
    [key: string]: unknown;
}

const US_STATE_NAME_TO_CODE = new Map<string, string>([
    ["alabama", "AL"],
    ["alaska", "AK"],
    ["american samoa", "AS"],
    ["arizona", "AZ"],
    ["arkansas", "AR"],
    ["california", "CA"],
    ["colorado", "CO"],
    ["connecticut", "CT"],
    ["delaware", "DE"],
    ["district of columbia", "DC"],
    ["washington d.c.", "DC"],
    ["washington dc", "DC"],
    ["washington, d.c.", "DC"],
    ["washington, dc", "DC"],
    ["d.c.", "DC"],
    ["dc", "DC"],
    ["federated states of micronesia", "FM"],
    ["florida", "FL"],
    ["georgia", "GA"],
    ["guam", "GU"],
    ["hawaii", "HI"],
    ["idaho", "ID"],
    ["illinois", "IL"],
    ["indiana", "IN"],
    ["iowa", "IA"],
    ["kansas", "KS"],
    ["kentucky", "KY"],
    ["louisiana", "LA"],
    ["maine", "ME"],
    ["marshall islands", "MH"],
    ["maryland", "MD"],
    ["massachusetts", "MA"],
    ["michigan", "MI"],
    ["minnesota", "MN"],
    ["mississippi", "MS"],
    ["missouri", "MO"],
    ["montana", "MT"],
    ["nebraska", "NE"],
    ["nevada", "NV"],
    ["new hampshire", "NH"],
    ["new jersey", "NJ"],
    ["new mexico", "NM"],
    ["new york", "NY"],
    ["north carolina", "NC"],
    ["north dakota", "ND"],
    ["northern mariana islands", "MP"],
    ["ohio", "OH"],
    ["oklahoma", "OK"],
    ["oregon", "OR"],
    ["palau", "PW"],
    ["pennsylvania", "PA"],
    ["puerto rico", "PR"],
    ["rhode island", "RI"],
    ["south carolina", "SC"],
    ["south dakota", "SD"],
    ["tennessee", "TN"],
    ["texas", "TX"],
    ["united states", "US"],
    ["utah", "UT"],
    ["vermont", "VT"],
    ["virgin islands", "VI"],
    ["u.s. virgin islands", "VI"],
    ["us virgin islands", "VI"],
    ["united states virgin islands", "VI"],
    ["virginia", "VA"],
    ["washington", "WA"],
    ["west virginia", "WV"],
    ["wisconsin", "WI"],
    ["wyoming", "WY"],
    ["armed forces americas", "AA"],
    ["armed forces europe", "AE"],
    ["armed forces pacific", "AP"],
]);

const STRICT_COORD_REGEX = /^[-+]?(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?$/;

const safeTrim = (val: unknown): string | undefined => {
    if (typeof val === "string") {
        const trimmed = val.trim();
        return trimmed.length > 0 ? trimmed : undefined;
    }
    if (typeof val === "number" && Number.isFinite(val)) {
        return String(val);
    }
    return undefined;
};

const sanitizeObject = <T extends Record<string, unknown>>(obj: unknown): T => {
    const clean = Object.create(null) as Record<string, unknown>;
    if (obj && typeof obj === "object" && !Array.isArray(obj)) {
        for (const key of Object.keys(obj)) {
            clean[key] = (obj as Record<string, unknown>)[key];
        }
    }
    return clean as T;
};

// @lat: [[address-normalization#Defensive coordinate parsing and validation bounds]]
const parseCoordinate = (coord: unknown, min: number, max: number): number | undefined => {
    let num: number;
    if (typeof coord === "number") {
        num = coord;
    } else if (typeof coord === "string") {
        const trimmed = coord.trim();
        if (trimmed.length === 0) return undefined;
        if (/^[-+]?0x/i.test(trimmed)) return undefined;
        if (!STRICT_COORD_REGEX.test(trimmed)) return undefined;
        num = Number(trimmed);
    } else {
        return undefined;
    }

    if (Number.isFinite(num) && num >= min && num <= max) {
        return num;
    }
    return undefined;
};

const resolveLocality = (address: INominatimAddress): string | undefined => {
    const candidates = [
        address.city,
        address.town,
        address.village,
        address.municipality,
        address.hamlet,
        address.borough,
        address.suburb,
        address.city_district,
        address.quarter,
        address.neighbourhood,
        address.neighborhood,
        address.county,
    ];

    for (const candidate of candidates) {
        const trimmed = safeTrim(candidate);
        if (trimmed) return trimmed;
    }
    return undefined;
};

// @lat: [[address-normalization#Region code resolution and casing]]
const resolveRegionCode = (address: INominatimAddress, region?: string): string | undefined => {
    const isoCode = safeTrim(address["ISO3166-2-lvl4"]);
    if (isoCode) {
        const match = /^[A-Za-z]{2}-([A-Za-z0-9]{2,3})$/.exec(isoCode);
        if (match?.[1]) {
            return match[1].toUpperCase();
        }
    }

    const stateCode = safeTrim(address.state_code);
    if (stateCode && stateCode.length === 2) {
        return stateCode.toUpperCase();
    }

    if (region) {
        const trimmed = region.trim();
        if (trimmed.length === 2) {
            return trimmed.toUpperCase();
        }
        const normalized = trimmed.toLowerCase().replace(/\s+/g, " ");
        const directLookup = US_STATE_NAME_TO_CODE.get(normalized);
        if (directLookup) return directLookup;

        const stripped = normalized.replace(/[.,]/g, "").replace(/\s+/g, " ").trim();
        const strippedLookup = US_STATE_NAME_TO_CODE.get(stripped);
        if (strippedLookup) return strippedLookup;
    }

    return undefined;
};

// @lat: [[address-normalization#Nominatim address parsing into canonical address attributes]]
export const parseNominatimAddress = (place?: INominatimPlace | null): TParsedNominatimAddress => {
    const parsed: TParsedNominatimAddress = Object.create(null);
    if (!place || typeof place !== "object" || Array.isArray(place)) return parsed;

    const cleanPlace = sanitizeObject<INominatimPlace>(place);

    const latitude = parseCoordinate(cleanPlace.lat, -90, 90);
    if (latitude !== undefined) parsed.latitude = latitude;

    const longitude = parseCoordinate(cleanPlace.lon, -180, 180);
    if (longitude !== undefined) parsed.longitude = longitude;

    const address = cleanPlace.address;
    if (!address || typeof address !== "object" || Array.isArray(address)) return parsed;

    const cleanAddress = sanitizeObject<INominatimAddress>(address);

    const houseNumber = safeTrim(cleanAddress.house_number);
    const road = safeTrim(
        cleanAddress.road ??
            cleanAddress.street ??
            cleanAddress.pedestrian ??
            cleanAddress.square ??
            cleanAddress.footway ??
            cleanAddress.cycleway ??
            cleanAddress.path,
    );
    if (houseNumber && road) {
        parsed.street = `${houseNumber} ${road}`;
    }

    const city = resolveLocality(cleanAddress);
    if (city) parsed.city = city;

    const region = safeTrim(cleanAddress.state ?? cleanAddress.region);
    if (region) parsed.region = region;

    const regionCode = resolveRegionCode(cleanAddress, region);
    if (regionCode) parsed.region_code = regionCode;

    const postalCode = safeTrim(cleanAddress.postcode);
    if (postalCode) parsed.postal_code = postalCode;

    const country = safeTrim(cleanAddress.country);
    if (country) {
        parsed.country = country;
    } else {
        const rawCountryCode = safeTrim(cleanAddress.country_code);
        const countryCode = rawCountryCode ? rawCountryCode.toLowerCase() : undefined;
        if (countryCode === "us") {
            parsed.country = "United States";
        } else if (countryCode && countryCode.length === 2) {
            parsed.country = countryCode.toUpperCase();
        }
    }

    return parsed;
};
