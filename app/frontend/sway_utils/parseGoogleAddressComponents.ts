// @lat: [[locale-extension#Nominatim geographic configuration]]
import type { sway } from "sway";

// @lat: [[inertia-user-prop-address-whitelist#Why TParsedGoogleAddress carries latitude/longitude but sway.IAddress does not]]
export type TParsedGoogleAddress = Partial<sway.IAddress> & {
    region?: string;
    latitude?: number;
    longitude?: number;
};

const longText = (components: google.maps.places.AddressComponent[], type: string): string | undefined =>
    components.find((component) => component.types.includes(type))?.longText ?? undefined;

const shortText = (components: google.maps.places.AddressComponent[], type: string): string | undefined =>
    components.find((component) => component.types.includes(type))?.shortText ?? undefined;

// @lat: [[inertia-user-prop-address-whitelist#Why TParsedGoogleAddress carries latitude/longitude but sway.IAddress does not]]
export const parseGoogleAddressComponents = (place: google.maps.places.Place): TParsedGoogleAddress => {
    const parsed: TParsedGoogleAddress = {};

    const { location } = place;
    if (location) {
        parsed.latitude = location.lat();
        parsed.longitude = location.lng();
    }

    const components = place.addressComponents ?? [];
    const streetNumber = longText(components, "street_number");
    const street = longText(components, "route");
    if (streetNumber && street) parsed.street = `${streetNumber} ${street}`;

    const city = longText(components, "locality");
    if (city) parsed.city = city;

    const region = longText(components, "administrative_area_level_1");
    if (region) parsed.region = region;

    const regionCode = shortText(components, "administrative_area_level_1");
    if (regionCode) parsed.region_code = regionCode;

    const postalCode = longText(components, "postal_code");
    if (postalCode) parsed.postal_code = postalCode;

    const country = longText(components, "country");
    if (country) parsed.country = country;

    return parsed;
};
