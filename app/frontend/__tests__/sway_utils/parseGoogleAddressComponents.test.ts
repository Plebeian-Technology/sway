import { describe, expect, it } from "vitest";

import { parseGoogleAddressComponents } from "app/frontend/sway_utils/parseGoogleAddressComponents";

type Component = google.maps.places.AddressComponent;

const component = (longText: string, shortText: string, types: string[]): Component =>
    ({ longText, shortText, types }) as Component;

const latLng = (lat: number, lng: number): google.maps.LatLng =>
    ({ lat: () => lat, lng: () => lng }) as google.maps.LatLng;

const place = (
    components: Component[],
    location: google.maps.LatLng | null = latLng(39.29, -76.61),
): google.maps.places.Place => ({ addressComponents: components, location }) as unknown as google.maps.places.Place;

const FULL = [
    component("1", "1", ["street_number"]),
    component("West Elm Street", "W Elm St", ["route"]),
    component("Baltimore", "Baltimore", ["locality", "political"]),
    component("Maryland", "MD", ["administrative_area_level_1", "political"]),
    component("21201", "21201", ["postal_code"]),
    component("United States", "US", ["country", "political"]),
];

describe("parseGoogleAddressComponents", () => {
    it("maps a complete Place to all eight address fields", () => {
        expect(parseGoogleAddressComponents(place(FULL))).toEqual({
            latitude: 39.29,
            longitude: -76.61,
            street: "1 West Elm Street",
            city: "Baltimore",
            region: "Maryland",
            region_code: "MD",
            postal_code: "21201",
            country: "United States",
        });
    });

    it("returns an empty object when the Place has no components or location", () => {
        expect(parseGoogleAddressComponents(place([], null))).toEqual({});
    });

    it("joins the street_number longText with the route longText", () => {
        expect(parseGoogleAddressComponents(place(FULL)).street).toBe("1 West Elm Street");
    });

    it("omits street when the street_number is missing", () => {
        const parsed = parseGoogleAddressComponents(place([component("West Elm Street", "W Elm St", ["route"])], null));
        expect(parsed.street).toBeUndefined();
    });

    it("omits street when the route is missing", () => {
        const parsed = parseGoogleAddressComponents(place([component("1", "1", ["street_number"])], null));
        expect(parsed.street).toBeUndefined();
    });

    it("takes region from longText and region_code from shortText of administrative_area_level_1", () => {
        const parsed = parseGoogleAddressComponents(
            place([component("Maryland", "MD", ["administrative_area_level_1", "political"])], null),
        );
        expect(parsed.region).toBe("Maryland");
        expect(parsed.region_code).toBe("MD");
    });

    it("omits region and region_code when administrative_area_level_1 is absent", () => {
        const parsed = parseGoogleAddressComponents(place([component("Baltimore", "Baltimore", ["locality"])], null));
        expect(parsed.region).toBeUndefined();
        expect(parsed.region_code).toBeUndefined();
    });

    it("omits city, postal_code and country when their components are absent", () => {
        const parsed = parseGoogleAddressComponents(
            place([component("Maryland", "MD", ["administrative_area_level_1"])], null),
        );
        expect(parsed.city).toBeUndefined();
        expect(parsed.postal_code).toBeUndefined();
        expect(parsed.country).toBeUndefined();
    });

    it("extracts latitude and longitude from the Place location", () => {
        const parsed = parseGoogleAddressComponents(place(FULL, latLng(12.5, -34.75)));
        expect(parsed.latitude).toBe(12.5);
        expect(parsed.longitude).toBe(-34.75);
    });
});
