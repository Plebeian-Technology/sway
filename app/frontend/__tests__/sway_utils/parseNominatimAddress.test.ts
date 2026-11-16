import { describe, expect, it } from "vitest";

import {
    type INominatimAddress,
    type INominatimPlace,
    parseNominatimAddress,
} from "app/frontend/sway_utils/parseNominatimAddress";

const mockPlace = (
    address: INominatimAddress | null = null,
    overrides: Partial<INominatimPlace> = {},
): INominatimPlace => {
    const place: INominatimPlace = {
        place_id: 100149,
        osm_type: "node",
        osm_id: 107775,
        lat: "39.29038",
        lon: "-76.61219",
        display_name: "City Hall, 100, Holliday Street, Baltimore, Maryland, 21202, United States",
        boundingbox: ["39.28038", "39.30038", "-76.62219", "-76.60219"],
        ...overrides,
    };

    if (address !== null) {
        place.address = address;
    }

    return place;
};

const BALTIMORE_ADDRESS: INominatimAddress = {
    house_number: "100",
    road: "Holliday Street",
    city: "Baltimore",
    state: "Maryland",
    "ISO3166-2-lvl4": "US-MD",
    postcode: "21202",
    country: "United States",
    country_code: "us",
};

describe("parseNominatimAddress", () => {
    describe("complete address mapping", () => {
        it("maps a complete Nominatim place to all eight Sway address fields", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS));

            expect(result).toEqual({
                latitude: 39.29038,
                longitude: -76.61219,
                street: "100 Holliday Street",
                city: "Baltimore",
                region: "Maryland",
                region_code: "MD",
                postal_code: "21202",
                country: "United States",
            });
        });
    });

    describe("locality / city fallback cascade", () => {
        it("uses city when present, ignoring lower-precedence locality tags", () => {
            const result = parseNominatimAddress(
                mockPlace({ ...BALTIMORE_ADDRESS, city: "Baltimore", town: "IgnoreTown", suburb: "Hampden" }),
            );
            expect(result.city).toBe("Baltimore");
        });

        it("falls back to town when city is absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, town: "Towson" }));
            expect(result.city).toBe("Towson");
        });

        it("falls back to village when city and town are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, village: "Bethesda" }));
            expect(result.city).toBe("Bethesda");
        });

        it("falls back to municipality when city, town, and village are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, municipality: "Ocean City" }));
            expect(result.city).toBe("Ocean City");
        });

        it("falls back to hamlet when higher order localities are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, hamlet: "Sparks" }));
            expect(result.city).toBe("Sparks");
        });

        it("falls back to borough when higher order localities are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, borough: "State College" }));
            expect(result.city).toBe("State College");
        });

        it("falls back to suburb when higher order localities are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, suburb: "Bethesda" }));
            expect(result.city).toBe("Bethesda");
        });

        it("falls back to city_district when higher order localities are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, city_district: "Downtown" }));
            expect(result.city).toBe("Downtown");
        });

        it("falls back to quarter when higher order localities are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, quarter: "Fells Point Quarter" }));
            expect(result.city).toBe("Fells Point Quarter");
        });

        it("falls back to neighbourhood when higher order localities are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, neighbourhood: "Mount Vernon" }));
            expect(result.city).toBe("Mount Vernon");
        });

        it("falls back to neighborhood spelling when higher order localities are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, neighborhood: "Federal Hill" }));
            expect(result.city).toBe("Federal Hill");
        });

        it("trims whitespace in locality", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, town: "  Towson  " }));
            expect(result.city).toBe("Towson");
        });

        it("skips empty string locality and cascades to next candidate", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, city: "   ", town: "Bel Air" }));
            expect(result.city).toBe("Bel Air");
        });

        it("omits city when no locality component is present", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace(withoutCity));
            expect(result.city).toBeUndefined();
        });
    });

    describe("state and region_code extraction", () => {
        it("maps full US state name to 2-letter region_code", () => {
            const result = parseNominatimAddress(
                mockPlace({ ...BALTIMORE_ADDRESS, state: "Maryland", "ISO3166-2-lvl4": undefined }),
            );
            expect(result.region).toBe("Maryland");
            expect(result.region_code).toBe("MD");
        });

        it("maps state name case-insensitively", () => {
            const result = parseNominatimAddress(
                mockPlace({ ...BALTIMORE_ADDRESS, state: "maryland", "ISO3166-2-lvl4": undefined }),
            );
            expect(result.region).toBe("maryland");
            expect(result.region_code).toBe("MD");
        });

        it("trims whitespace from state name", () => {
            const result = parseNominatimAddress(
                mockPlace({ ...BALTIMORE_ADDRESS, state: "  Maryland  ", "ISO3166-2-lvl4": undefined }),
            );
            expect(result.region).toBe("Maryland");
            expect(result.region_code).toBe("MD");
        });

        it("maps multi-word US states correctly", () => {
            const result = parseNominatimAddress(
                mockPlace({ ...BALTIMORE_ADDRESS, state: "New York", "ISO3166-2-lvl4": undefined }),
            );
            expect(result.region).toBe("New York");
            expect(result.region_code).toBe("NY");
        });

        it("maps District of Columbia variations", () => {
            expect(
                parseNominatimAddress(
                    mockPlace({ ...BALTIMORE_ADDRESS, state: "District of Columbia", "ISO3166-2-lvl4": undefined }),
                ).region_code,
            ).toBe("DC");
            expect(
                parseNominatimAddress(
                    mockPlace({ ...BALTIMORE_ADDRESS, state: "Washington DC", "ISO3166-2-lvl4": undefined }),
                ).region_code,
            ).toBe("DC");
            expect(
                parseNominatimAddress(
                    mockPlace({ ...BALTIMORE_ADDRESS, state: "Washington, D.C.", "ISO3166-2-lvl4": undefined }),
                ).region_code,
            ).toBe("DC");
        });

        it("maps US territories and associated states", () => {
            expect(
                parseNominatimAddress(
                    mockPlace({ ...BALTIMORE_ADDRESS, state: "Puerto Rico", "ISO3166-2-lvl4": undefined }),
                ).region_code,
            ).toBe("PR");
            expect(
                parseNominatimAddress(mockPlace({ ...BALTIMORE_ADDRESS, state: "Guam", "ISO3166-2-lvl4": undefined }))
                    .region_code,
            ).toBe("GU");
            expect(
                parseNominatimAddress(
                    mockPlace({ ...BALTIMORE_ADDRESS, state: "Virgin Islands", "ISO3166-2-lvl4": undefined }),
                ).region_code,
            ).toBe("VI");
        });

        it("maps military postal states (AA, AE, AP)", () => {
            expect(
                parseNominatimAddress(
                    mockPlace({ ...BALTIMORE_ADDRESS, state: "Armed Forces Europe", "ISO3166-2-lvl4": undefined }),
                ).region_code,
            ).toBe("AE");
        });

        it("handles 2-letter state code directly in state", () => {
            const result = parseNominatimAddress(
                mockPlace({ ...BALTIMORE_ADDRESS, state: "MD", "ISO3166-2-lvl4": undefined }),
            );
            expect(result.region).toBe("MD");
            expect(result.region_code).toBe("MD");
        });

        it("handles 2-letter lowercase state code directly in state", () => {
            const result = parseNominatimAddress(
                mockPlace({ ...BALTIMORE_ADDRESS, state: "md", "ISO3166-2-lvl4": undefined }),
            );
            expect(result.region).toBe("md");
            expect(result.region_code).toBe("MD");
        });

        it("extracts region_code from state_code property", () => {
            const result = parseNominatimAddress(
                mockPlace({
                    ...BALTIMORE_ADDRESS,
                    state: "Maryland",
                    state_code: "MD",
                    "ISO3166-2-lvl4": undefined,
                }),
            );
            expect(result.region_code).toBe("MD");
        });

        it("extracts region_code from ISO3166-2-lvl4 property", () => {
            const result = parseNominatimAddress(
                mockPlace({
                    ...BALTIMORE_ADDRESS,
                    state: "Maryland",
                    "ISO3166-2-lvl4": "US-MD",
                }),
            );
            expect(result.region_code).toBe("MD");
        });

        it("falls back to region property when state is absent", () => {
            const { state: _, ...withoutState } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(
                mockPlace({ ...withoutState, region: "Maryland", "ISO3166-2-lvl4": undefined }),
            );
            expect(result.region).toBe("Maryland");
            expect(result.region_code).toBe("MD");
        });

        it("omits region_code for unknown non-US regions while preserving region name", () => {
            const result = parseNominatimAddress(
                mockPlace({
                    ...BALTIMORE_ADDRESS,
                    state: "Bavaria",
                    "ISO3166-2-lvl4": undefined,
                    state_code: undefined,
                }),
            );
            expect(result.region).toBe("Bavaria");
            expect(result.region_code).toBeUndefined();
        });

        it("omits both region and region_code when state and region are absent", () => {
            const { state: _, ...withoutState } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(
                mockPlace({ ...withoutState, "ISO3166-2-lvl4": undefined, state_code: undefined }),
            );
            expect(result.region).toBeUndefined();
            expect(result.region_code).toBeUndefined();
        });
    });

    describe("street composition", () => {
        it("combines house_number and road with trimming", () => {
            const result = parseNominatimAddress(
                mockPlace({ ...BALTIMORE_ADDRESS, house_number: " 100 ", road: " Holliday Street " }),
            );
            expect(result.street).toBe("100 Holliday Street");
        });

        it("omits street when house_number is missing", () => {
            const { house_number: _, ...withoutNumber } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace(withoutNumber));
            expect(result.street).toBeUndefined();
        });

        it("omits street when road is missing", () => {
            const { road: _, ...withoutRoad } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace(withoutRoad));
            expect(result.street).toBeUndefined();
        });

        it("omits street when house_number is empty string", () => {
            const result = parseNominatimAddress(mockPlace({ ...BALTIMORE_ADDRESS, house_number: "   " }));
            expect(result.street).toBeUndefined();
        });

        it("omits street when road is empty string", () => {
            const result = parseNominatimAddress(mockPlace({ ...BALTIMORE_ADDRESS, road: "   " }));
            expect(result.street).toBeUndefined();
        });

        it("falls back to street tag when road is absent", () => {
            const { road: _, ...withoutRoad } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutRoad, house_number: "100", street: "Main St" }));
            expect(result.street).toBe("100 Main St");
        });

        it("falls back to pedestrian tag when road and street are absent", () => {
            const { road: _, ...withoutRoad } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(
                mockPlace({ ...withoutRoad, house_number: "50", pedestrian: "Pratt Street Promenade" }),
            );
            expect(result.street).toBe("50 Pratt Street Promenade");
        });

        it("falls back to square tag when road is absent", () => {
            const { road: _, ...withoutRoad } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(
                mockPlace({ ...withoutRoad, house_number: "1", square: "Market Square" }),
            );
            expect(result.street).toBe("1 Market Square");
        });
    });

    describe("postal code and country handling", () => {
        it("trims postal code", () => {
            const result = parseNominatimAddress(mockPlace({ ...BALTIMORE_ADDRESS, postcode: "  21202  " }));
            expect(result.postal_code).toBe("21202");
        });

        it("omits postal code when postcode is absent or empty string", () => {
            const { postcode: _, ...withoutPostcode } = BALTIMORE_ADDRESS;
            expect(parseNominatimAddress(mockPlace(withoutPostcode)).postal_code).toBeUndefined();
            expect(
                parseNominatimAddress(mockPlace({ ...withoutPostcode, postcode: "   " })).postal_code,
            ).toBeUndefined();
        });

        it("trims country name", () => {
            const result = parseNominatimAddress(mockPlace({ ...BALTIMORE_ADDRESS, country: "  United States  " }));
            expect(result.country).toBe("United States");
        });

        it("falls back to 'United States' when country is missing but country_code is 'us'", () => {
            const { country: _, ...withoutCountry } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCountry, country_code: "us" }));
            expect(result.country).toBe("United States");
        });

        it("falls back to 'United States' when country is missing but country_code is uppercase 'US'", () => {
            const { country: _, ...withoutCountry } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCountry, country_code: "US" }));
            expect(result.country).toBe("United States");
        });

        it("falls back to uppercase country_code when country is missing and non-US", () => {
            const { country: _, ...withoutCountry } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCountry, country_code: "ca" }));
            expect(result.country).toBe("CA");
        });

        it("omits country when both country and country_code are absent", () => {
            const { country: _, country_code: __, ...withoutCountry } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace(withoutCountry));
            expect(result.country).toBeUndefined();
        });
    });

    describe("coordinates parsing and precision", () => {
        it("parses string lat and lon as float numbers", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS, { lat: "39.29038", lon: "-76.61219" }));
            expect(result.latitude).toBe(39.29038);
            expect(result.longitude).toBe(-76.61219);
        });

        it("accepts numeric lat and lon directly", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS, { lat: 39.29038, lon: -76.61219 }));
            expect(result.latitude).toBe(39.29038);
            expect(result.longitude).toBe(-76.61219);
        });

        it("correctly preserves zero coordinates", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS, { lat: "0", lon: "0" }));
            expect(result.latitude).toBe(0);
            expect(result.longitude).toBe(0);
        });

        it("omits latitude and longitude when lat and lon are non-numeric strings", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS, { lat: "invalid", lon: "nan" }));
            expect(result.latitude).toBeUndefined();
            expect(result.longitude).toBeUndefined();
        });

        it("omits latitude and longitude when coordinates are empty strings", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS, { lat: "   ", lon: "   " }));
            expect(result.latitude).toBeUndefined();
            expect(result.longitude).toBeUndefined();
        });

        it("omits latitude when out of valid [-90, 90] bounds", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS, { lat: "95.0", lon: "-76.61219" }));
            expect(result.latitude).toBeUndefined();
            expect(result.longitude).toBe(-76.61219);
        });

        it("omits longitude when out of valid [-180, 180] bounds", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS, { lat: "39.29038", lon: "195.0" }));
            expect(result.latitude).toBe(39.29038);
            expect(result.longitude).toBeUndefined();
        });

        it("omits latitude and longitude when lat and lon are absent", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS, { lat: undefined, lon: undefined }));
            expect(result.latitude).toBeUndefined();
            expect(result.longitude).toBeUndefined();
        });
    });

    describe("defensive guards and edge cases", () => {
        it("returns an empty object when place is null", () => {
            expect(parseNominatimAddress(null)).toEqual({});
        });

        it("returns an empty object when place is undefined", () => {
            expect(parseNominatimAddress(undefined)).toEqual({});
        });

        it("returns an empty object when place is empty object", () => {
            expect(parseNominatimAddress({} as INominatimPlace)).toEqual({});
        });

        it("returns an empty object when place is a primitive non-object", () => {
            expect(parseNominatimAddress("not-an-object" as unknown as INominatimPlace)).toEqual({});
            expect(parseNominatimAddress(12345 as unknown as INominatimPlace)).toEqual({});
        });

        it("parses coordinates even when address property is absent", () => {
            const result = parseNominatimAddress({ lat: "39.29038", lon: "-76.61219" } as INominatimPlace);
            expect(result).toEqual({
                latitude: 39.29038,
                longitude: -76.61219,
            });
        });

        it("returns an empty object when address property is an empty object", () => {
            expect(parseNominatimAddress({ address: {} } as INominatimPlace)).toEqual({});
        });

        it("does not leak arbitrary OSM metadata onto the parsed address object", () => {
            const result = parseNominatimAddress({
                place_id: 99999,
                osm_type: "way",
                osm_id: 123456,
                licence: "ODbL",
                boundingbox: ["1", "2", "3", "4"],
                display_name: "Some Display String",
                class: "building",
                type: "yes",
                importance: 0.85,
                address: BALTIMORE_ADDRESS,
            } as INominatimPlace);

            const keys = Object.keys(result);
            expect(keys.sort()).toEqual(["city", "country", "postal_code", "region", "region_code", "street"]);
        });
    });

    describe("defensive input coercion and regression prevention", () => {
        it("coerces numeric house_number and postcode into strings", () => {
            const result = parseNominatimAddress(
                mockPlace({
                    ...BALTIMORE_ADDRESS,
                    house_number: 100 as unknown as string,
                    postcode: 21202 as unknown as string,
                }),
            );
            expect(result.street).toBe("100 Holliday Street");
            expect(result.postal_code).toBe("21202");
        });

        it("safely ignores array and boolean address fields without throwing TypeError", () => {
            const malformed = mockPlace({
                ...BALTIMORE_ADDRESS,
                house_number: ["100"] as unknown as string,
                road: true as unknown as string,
                state: false as unknown as string,
                postcode: [21202] as unknown as string,
            });

            expect(() => parseNominatimAddress(malformed)).not.toThrow();
            const result = parseNominatimAddress(malformed);
            expect(result.street).toBeUndefined();
            expect(result.postal_code).toBeUndefined();
        });

        it("rejects hexadecimal coordinate strings", () => {
            const result = parseNominatimAddress(mockPlace(BALTIMORE_ADDRESS, { lat: "0x10", lon: "-0x40" }));
            expect(result.latitude).toBeUndefined();
            expect(result.longitude).toBeUndefined();
        });

        it("rejects coordinate strings with trailing garbage characters", () => {
            const result = parseNominatimAddress(
                mockPlace(BALTIMORE_ADDRESS, { lat: "39.29038foo", lon: "-76.61219bar" }),
            );
            expect(result.latitude).toBeUndefined();
            expect(result.longitude).toBeUndefined();
        });

        it("maps Washington, DC with comma and no periods to DC region_code", () => {
            const result = parseNominatimAddress(
                mockPlace({
                    ...BALTIMORE_ADDRESS,
                    state: "Washington, DC",
                    "ISO3166-2-lvl4": undefined,
                }),
            );
            expect(result.region_code).toBe("DC");
        });

        it("falls back to county when all municipal locality tags are absent", () => {
            const { city: _, ...withoutCity } = BALTIMORE_ADDRESS;
            const result = parseNominatimAddress(mockPlace({ ...withoutCity, county: "Queen Anne's County" }));
            expect(result.city).toBe("Queen Anne's County");
        });

        it("ignores malformed ISO3166-2-lvl4 codes and resolves state names after punctuation stripping", () => {
            const result = parseNominatimAddress(
                mockPlace({
                    ...BALTIMORE_ADDRESS,
                    "ISO3166-2-lvl4": "not-an-iso-code",
                    state_code: undefined,
                    state: "Mary.land.",
                }),
            );
            expect(result.region_code).toBe("MD");
        });

        it("defends against prototype pollution on Object.prototype", () => {
            try {
                (Object.prototype as Record<string, unknown>).city = "PollutedCity";
                (Object.prototype as Record<string, unknown>).lat = "39.29038";

                const clean = parseNominatimAddress({ address: {} });
                expect(clean.city).toBeUndefined();
                expect(clean.latitude).toBeUndefined();
            } finally {
                delete (Object.prototype as Record<string, unknown>).city;
                delete (Object.prototype as Record<string, unknown>).lat;
            }
        });
    });
});
