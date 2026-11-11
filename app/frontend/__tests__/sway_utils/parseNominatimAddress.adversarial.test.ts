import { describe, expect, it } from "vitest";

import {
    type INominatimAddress,
    type INominatimPlace,
    parseNominatimAddress,
} from "app/frontend/sway_utils/parseNominatimAddress";

describe("parseNominatimAddress — Adversarial & Parity Test Suite", () => {
    describe("Parity & Real-World Maryland / DC Regional OSM Responses", () => {
        it("handles Baltimore City (independent city with admin_level=6)", () => {
            const place: INominatimPlace = {
                place_id: 1001,
                lat: "39.29038",
                lon: "-76.61219",
                display_name: "100, Holliday Street, Downtown, Baltimore, Maryland, 21202, United States",
                address: {
                    house_number: "100",
                    road: "Holliday Street",
                    suburb: "Downtown",
                    city: "Baltimore",
                    state: "Maryland",
                    "ISO3166-2-lvl4": "US-MD",
                    postcode: "21202",
                    country: "United States",
                    country_code: "us",
                },
            };

            const result = parseNominatimAddress(place);
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

        it("handles Montgomery County — Bethesda (unincorporated CDP with town/suburb)", () => {
            const place: INominatimPlace = {
                place_id: 2001,
                lat: "38.9847",
                lon: "-77.0947",
                display_name: "7201, Wisconsin Avenue, Bethesda, Montgomery County, Maryland, 20814, United States",
                address: {
                    house_number: "7201",
                    road: "Wisconsin Avenue",
                    town: "Bethesda",
                    county: "Montgomery County",
                    state: "Maryland",
                    "ISO3166-2-lvl4": "US-MD",
                    postcode: "20814",
                    country: "United States",
                    country_code: "us",
                },
            };

            const result = parseNominatimAddress(place);
            expect(result.city).toBe("Bethesda");
            expect(result.region_code).toBe("MD");
            expect(result.street).toBe("7201 Wisconsin Avenue");
            expect(result.postal_code).toBe("20814");
        });

        it("handles Montgomery County — Silver Spring (unincorporated CDP with suburb tag)", () => {
            const place: INominatimPlace = {
                place_id: 2002,
                lat: "38.9959",
                lon: "-77.0276",
                display_name: "8455, Colesville Road, Silver Spring, Montgomery County, Maryland, 20910, United States",
                address: {
                    house_number: "8455",
                    road: "Colesville Road",
                    suburb: "Silver Spring",
                    county: "Montgomery County",
                    state: "Maryland",
                    "ISO3166-2-lvl4": "US-MD",
                    postcode: "20910",
                    country: "United States",
                    country_code: "us",
                },
            };

            const result = parseNominatimAddress(place);
            expect(result.city).toBe("Silver Spring");
            expect(result.region_code).toBe("MD");
            expect(result.street).toBe("8455 Colesville Road");
            expect(result.postal_code).toBe("20910");
        });

        it("handles Anne Arundel County — Annapolis (incorporated city)", () => {
            const place: INominatimPlace = {
                place_id: 3001,
                lat: "38.9784",
                lon: "-76.4922",
                display_name: "100, State Circle, Annapolis, Anne Arundel County, Maryland, 21401, United States",
                address: {
                    house_number: "100",
                    road: "State Circle",
                    city: "Annapolis",
                    county: "Anne Arundel County",
                    state: "Maryland",
                    "ISO3166-2-lvl4": "US-MD",
                    postcode: "21401",
                    country: "United States",
                    country_code: "us",
                },
            };

            const result = parseNominatimAddress(place);
            expect(result.city).toBe("Annapolis");
            expect(result.region_code).toBe("MD");
            expect(result.street).toBe("100 State Circle");
        });

        it("handles Prince George's County — College Park (city)", () => {
            const place: INominatimPlace = {
                place_id: 4001,
                lat: "38.9807",
                lon: "-76.9370",
                display_name:
                    "7401, Baltimore Avenue, College Park, Prince George's County, Maryland, 20740, United States",
                address: {
                    house_number: "7401",
                    road: "Baltimore Avenue",
                    city: "College Park",
                    county: "Prince George's County",
                    state: "Maryland",
                    "ISO3166-2-lvl4": "US-MD",
                    postcode: "20740",
                    country: "United States",
                    country_code: "us",
                },
            };

            const result = parseNominatimAddress(place);
            expect(result.city).toBe("College Park");
            expect(result.region_code).toBe("MD");
            expect(result.street).toBe("7401 Baltimore Avenue");
        });

        it("handles Washington D.C. (District of Columbia)", () => {
            const place: INominatimPlace = {
                place_id: 5001,
                lat: "38.8977",
                lon: "-77.0365",
                display_name:
                    "1600, Pennsylvania Avenue Northwest, Downtown, Washington, District of Columbia, 20500, United States",
                address: {
                    house_number: "1600",
                    road: "Pennsylvania Avenue Northwest",
                    city: "Washington",
                    state: "District of Columbia",
                    "ISO3166-2-lvl4": "US-DC",
                    postcode: "20500",
                    country: "United States",
                    country_code: "us",
                },
            };

            const result = parseNominatimAddress(place);
            expect(result).toEqual({
                latitude: 38.8977,
                longitude: -77.0365,
                street: "1600 Pennsylvania Avenue Northwest",
                city: "Washington",
                region: "District of Columbia",
                region_code: "DC",
                postal_code: "20500",
                country: "United States",
            });
        });

        it("handles Washington DC state variation 'Washington, DC' without ISO code", () => {
            const place: INominatimPlace = {
                address: {
                    house_number: "1600",
                    road: "Pennsylvania Ave NW",
                    city: "Washington",
                    state: "Washington, DC",
                    postcode: "20500",
                },
            };

            const result = parseNominatimAddress(place);
            expect(result.region_code).toBe("DC");
            expect(result.city).toBe("Washington");
        });

        it("handles rural Eastern Shore address with ONLY county as locality fallback", () => {
            const place: INominatimPlace = {
                place_id: 6001,
                lat: "38.9800",
                lon: "-76.1500",
                display_name: "12345, Crosby Road, Queen Anne's County, Maryland, 21619, United States",
                address: {
                    house_number: "12345",
                    road: "Crosby Road",
                    county: "Queen Anne's County",
                    state: "Maryland",
                    "ISO3166-2-lvl4": "US-MD",
                    postcode: "21619",
                    country: "United States",
                    country_code: "us",
                },
            };

            const result = parseNominatimAddress(place);
            expect(result.city).toBe("Queen Anne's County");
            expect(result.street).toBe("12345 Crosby Road");
            expect(result.region_code).toBe("MD");
        });

        it("handles footway, cycleway, and path road fallbacks", () => {
            expect(
                parseNominatimAddress({
                    address: { house_number: "500", footway: "Ocean City Boardwalk" },
                }).street,
            ).toBe("500 Ocean City Boardwalk");

            expect(
                parseNominatimAddress({
                    address: { house_number: "12", cycleway: "B&A Trail" },
                }).street,
            ).toBe("12 B&A Trail");

            expect(
                parseNominatimAddress({
                    address: { house_number: "1", path: "Appalachian Trail" },
                }).street,
            ).toBe("1 Appalachian Trail");
        });
    });

    describe("Backend Registration Compatibility with RegionUtil and SwayRegistrationController", () => {
        it("maps all 50 US states to exact 2-letter codes matching RegionUtil", () => {
            const states = [
                ["Alabama", "AL"],
                ["Alaska", "AK"],
                ["Arizona", "AZ"],
                ["Arkansas", "AR"],
                ["California", "CA"],
                ["Colorado", "CO"],
                ["Connecticut", "CT"],
                ["Delaware", "DE"],
                ["Florida", "FL"],
                ["Georgia", "GA"],
                ["Hawaii", "HI"],
                ["Idaho", "ID"],
                ["Illinois", "IL"],
                ["Indiana", "IN"],
                ["Iowa", "IA"],
                ["Kansas", "KS"],
                ["Kentucky", "KY"],
                ["Louisiana", "LA"],
                ["Maine", "ME"],
                ["Maryland", "MD"],
                ["Massachusetts", "MA"],
                ["Michigan", "MI"],
                ["Minnesota", "MN"],
                ["Mississippi", "MS"],
                ["Missouri", "MO"],
                ["Montana", "MT"],
                ["Nebraska", "NE"],
                ["Nevada", "NV"],
                ["New Hampshire", "NH"],
                ["New Jersey", "NJ"],
                ["New Mexico", "NM"],
                ["New York", "NY"],
                ["North Carolina", "NC"],
                ["North Dakota", "ND"],
                ["Ohio", "OH"],
                ["Oklahoma", "OK"],
                ["Oregon", "OR"],
                ["Pennsylvania", "PA"],
                ["Rhode Island", "RI"],
                ["South Carolina", "SC"],
                ["South Dakota", "SD"],
                ["Tennessee", "TN"],
                ["Texas", "TX"],
                ["Utah", "UT"],
                ["Vermont", "VT"],
                ["Virginia", "VA"],
                ["Washington", "WA"],
                ["West Virginia", "WV"],
                ["Wisconsin", "WI"],
                ["Wyoming", "WY"],
            ];

            for (const [stateName, expectedCode] of states) {
                const result = parseNominatimAddress({
                    address: { state: stateName } as INominatimAddress,
                });
                expect(result.region_code).toBe(expectedCode);
            }
        });

        it("maps US territories and commonwealths matching RegionUtil", () => {
            const territories = [
                ["Puerto Rico", "PR"],
                ["Guam", "GU"],
                ["Virgin Islands", "VI"],
                ["American Samoa", "AS"],
                ["Northern Mariana Islands", "MP"],
                ["Federated States Of Micronesia", "FM"],
                ["Marshall Islands", "MH"],
                ["Palau", "PW"],
            ];

            for (const [name, expectedCode] of territories) {
                const result = parseNominatimAddress({
                    address: { state: name } as INominatimAddress,
                });
                expect(result.region_code).toBe(expectedCode);
            }
        });
    });

    describe("Defensive Edge Cases & Malicious/Bizarre Input Structures", () => {
        it("gracefully handles place.address as a string instead of object", () => {
            const place = {
                lat: "39.29",
                lon: "-76.61",
                address: "100 Holliday Street, Baltimore, MD 21202",
            } as unknown as INominatimPlace;

            const result = parseNominatimAddress(place);
            expect(result).toEqual({
                latitude: 39.29,
                longitude: -76.61,
            });
        });

        it("handles null-prototype objects without error", () => {
            const address = Object.create(null);
            address.house_number = "100";
            address.road = "Holliday Street";
            address.city = "Baltimore";
            address.state = "Maryland";

            const place = Object.create(null);
            place.lat = "39.29";
            place.lon = "-76.61";
            place.address = address;

            const result = parseNominatimAddress(place as INominatimPlace);
            expect(result.city).toBe("Baltimore");
            expect(result.street).toBe("100 Holliday Street");
            expect(result.region_code).toBe("MD");
        });

        it("survives extreme coordinate boundaries and non-finite floats", () => {
            expect(parseNominatimAddress({ lat: "-90", lon: "-180" } as INominatimPlace)).toEqual({
                latitude: -90,
                longitude: -180,
            });
            expect(parseNominatimAddress({ lat: "90", lon: "180" } as INominatimPlace)).toEqual({
                latitude: 90,
                longitude: 180,
            });
            expect(parseNominatimAddress({ lat: "90.00001", lon: "0" } as INominatimPlace).latitude).toBeUndefined();
            expect(parseNominatimAddress({ lat: "-90.00001", lon: "0" } as INominatimPlace).latitude).toBeUndefined();
            expect(parseNominatimAddress({ lat: "0", lon: "180.00001" } as INominatimPlace).longitude).toBeUndefined();
            expect(parseNominatimAddress({ lat: "0", lon: "-180.00001" } as INominatimPlace).longitude).toBeUndefined();
        });

        it("rejects hexadecimal coordinate strings and does not parse as 0", () => {
            const result = parseNominatimAddress({
                lat: "0x10",
                lon: "0x40",
            } as INominatimPlace);

            expect(result.latitude).toBeUndefined();
            expect(result.longitude).toBeUndefined();

            expect(parseNominatimAddress({ lat: "-0x10", lon: "0" } as INominatimPlace).latitude).toBeUndefined();
        });

        it("rejects coordinates with trailing garbage characters", () => {
            const result = parseNominatimAddress({
                lat: "39.29038foo",
                lon: "-76.61219bar",
            } as INominatimPlace);

            expect(result.latitude).toBeUndefined();
            expect(result.longitude).toBeUndefined();
        });

        it("safely handles numeric fields without throwing TypeError", () => {
            const placeWithNumericValues: INominatimPlace = {
                address: {
                    house_number: 100,
                    road: "Holliday St",
                    postcode: 21202,
                },
            };

            const result = parseNominatimAddress(placeWithNumericValues);
            expect(result.street).toBe("100 Holliday St");
            expect(result.postal_code).toBe("21202");
        });

        it("safely ignores arrays, booleans, and objects without throwing TypeError", () => {
            const malformedPlace = {
                address: {
                    house_number: ["100"],
                    road: { name: "Holliday St" },
                    state: true,
                    country: ["United States"],
                    country_code: false,
                    postcode: {},
                },
            } as unknown as INominatimPlace;

            expect(() => parseNominatimAddress(malformedPlace)).not.toThrow();
            const result = parseNominatimAddress(malformedPlace);
            expect(result.street).toBeUndefined();
            expect(result.postal_code).toBeUndefined();
            expect(result.region).toBeUndefined();
        });

        it("defends against prototype pollution when Object.prototype is polluted", () => {
            try {
                (Object.prototype as any).city = "PollutedCity";
                (Object.prototype as any).state = "PollutedState";
                (Object.prototype as any).lat = "39.29038";
                (Object.prototype as any).lon = "-76.61219";

                const cleanPlace: INominatimPlace = {
                    address: {} as INominatimAddress,
                };

                const result = parseNominatimAddress(cleanPlace);

                expect(result.city).toBeUndefined();
                expect(result.region).toBeUndefined();
                expect(result.latitude).toBeUndefined();
                expect(result.longitude).toBeUndefined();
            } finally {
                delete (Object.prototype as any).city;
                delete (Object.prototype as any).state;
                delete (Object.prototype as any).lat;
                delete (Object.prototype as any).lon;
            }
        });
    });

    describe("Exhaustive Hexadecimal Coordinate Invalidation", () => {
        const hexCoords = [
            "0x10",
            "-0x20",
            "+0x10",
            "0XFF",
            "0x0",
            "-0x0",
            "+0x0",
            "0X0",
            "0x1a",
            "-0x1F",
            "+0xAB",
            "0x000",
            "0x1p-2",
            "0x",
            "-0x",
            "+0x",
            "0X10",
            "-0X20",
            " 0x10 ",
            "\t0x10\n",
            "0xdeadbeef",
            "-0xdeadbeef",
            "0x2A",
            "-0x2A",
        ];

        for (const hex of hexCoords) {
            it(`invalidates hex coordinate lat='${hex}' without parsing as 0 or float`, () => {
                const result = parseNominatimAddress({ lat: hex, lon: "0" } as INominatimPlace);
                expect(result.latitude).toBeUndefined();
            });

            it(`invalidates hex coordinate lon='${hex}' without parsing as 0 or float`, () => {
                const result = parseNominatimAddress({ lat: "0", lon: hex } as INominatimPlace);
                expect(result.longitude).toBeUndefined();
            });
        }
    });

    describe("Exhaustive Trailing Garbage Coordinate Invalidation", () => {
        const garbageCoords = [
            "39.29038foo",
            "-76.61219bar",
            "39.29 0",
            "39.29\0",
            "39.29\x00123",
            "39.29\t1",
            "39.29\r1",
            "39.29\n1",
            "39.29abc",
            "39.29.30",
            "--39.29",
            "++39.29",
            "+-39.29",
            "-+39.29",
            "39.29deg",
            "39°17'N",
            "39.29, -76.61",
            "39.29; drop table",
            "39.29<script>",
            ".39.29",
            "39..29",
            "39.29.",
            "39.29e",
            "39.29e+",
            "39.29e-",
            "39.29 e1",
            "39.29e1.5",
            "39.29f",
            "39.29d",
            "39.29L",
            "NaNfoo",
            "Infinitybar",
            "-Infinitybaz",
            "0b1010",
            "0o755",
            "1_000.5",
        ];

        for (const garbage of garbageCoords) {
            it(`invalidates trailing garbage coordinate lat='${garbage}'`, () => {
                const result = parseNominatimAddress({ lat: garbage, lon: "-76.61" } as INominatimPlace);
                expect(result.latitude).toBeUndefined();
            });

            it(`invalidates trailing garbage coordinate lon='${garbage}'`, () => {
                const result = parseNominatimAddress({ lat: "39.29", lon: garbage } as INominatimPlace);
                expect(result.longitude).toBeUndefined();
            });
        }
    });

    describe("Deep Prototype Pollution Resistance on Object.prototype", () => {
        const pollutedProps: Record<string, unknown> = {
            city: "PollutedCity",
            town: "PollutedTown",
            village: "PollutedVillage",
            municipality: "PollutedMunicipality",
            hamlet: "PollutedHamlet",
            borough: "PollutedBorough",
            suburb: "PollutedSuburb",
            city_district: "PollutedCityDistrict",
            quarter: "PollutedQuarter",
            neighbourhood: "PollutedNeighbourhood",
            neighborhood: "PollutedNeighborhood",
            county: "PollutedCounty",
            state: "PollutedState",
            region: "PollutedRegion",
            state_code: "PS",
            "ISO3166-2-lvl4": "US-PS",
            postcode: "99999",
            country: "PollutedCountry",
            country_code: "pc",
            house_number: "999",
            road: "PollutedRoad",
            street: "PollutedStreet",
            pedestrian: "PollutedPedestrian",
            square: "PollutedSquare",
            footway: "PollutedFootway",
            cycleway: "PollutedCycleway",
            path: "PollutedPath",
            lat: "39.29038",
            lon: "-76.61219",
        };

        it("completely isolates clean payloads from Object.prototype pollution across all fields", () => {
            try {
                for (const [prop, val] of Object.entries(pollutedProps)) {
                    (Object.prototype as any)[prop] = val;
                }

                const cleanResult = parseNominatimAddress({ address: {} } as INominatimPlace);
                expect(cleanResult.city).toBeUndefined();
                expect(cleanResult.street).toBeUndefined();
                expect(cleanResult.region).toBeUndefined();
                expect(cleanResult.region_code).toBeUndefined();
                expect(cleanResult.postal_code).toBeUndefined();
                expect(cleanResult.country).toBeUndefined();
                expect(cleanResult.latitude).toBeUndefined();
                expect(cleanResult.longitude).toBeUndefined();
                expect(Object.keys(cleanResult)).toEqual([]);

                const nullAddrResult = parseNominatimAddress({ address: undefined } as INominatimPlace);
                expect(Object.keys(nullAddrResult)).toEqual([]);

                const emptyResult = parseNominatimAddress({} as INominatimPlace);
                expect(Object.keys(emptyResult)).toEqual([]);

                const jsonProto = JSON.parse('{"__proto__": {"road": "evil", "city": "evil"}, "address": {}}');
                const jsonResult = parseNominatimAddress(jsonProto);
                expect(jsonResult.city).toBeUndefined();
                expect(jsonResult.street).toBeUndefined();
                expect(Object.keys(jsonResult)).toEqual([]);
            } finally {
                for (const prop of Object.keys(pollutedProps)) {
                    delete (Object.prototype as any)[prop];
                }
            }
        });
    });

    describe("Numeric Input Coercion and Edge Cases", () => {
        it("coerces numeric zero (0) in house_number and postcode", () => {
            const result = parseNominatimAddress({
                address: {
                    house_number: 0,
                    road: "Zero Way",
                    postcode: 0,
                },
            } as INominatimPlace);

            expect(result.street).toBe("0 Zero Way");
            expect(result.postal_code).toBe("0");
        });

        it("coerces negative and floating point numbers in house_number", () => {
            const resultFloat = parseNominatimAddress({
                address: {
                    house_number: 100.5,
                    road: "Split Lot Ave",
                    postcode: 12345,
                },
            } as INominatimPlace);
            expect(resultFloat.street).toBe("100.5 Split Lot Ave");
            expect(resultFloat.postal_code).toBe("12345");

            const resultNeg = parseNominatimAddress({
                address: {
                    house_number: -42,
                    road: "Basement St",
                },
            } as INominatimPlace);
            expect(resultNeg.street).toBe("-42 Basement St");
        });

        it("safely handles non-finite numeric inputs (NaN, Infinity, -Infinity) returning undefined", () => {
            const result = parseNominatimAddress({
                lat: NaN,
                lon: Infinity,
                address: {
                    house_number: NaN,
                    road: "Infinity Loop",
                    postcode: -Infinity,
                    city: NaN,
                    state: Infinity,
                },
            } as unknown as INominatimPlace);

            expect(result.latitude).toBeUndefined();
            expect(result.longitude).toBeUndefined();
            expect(result.street).toBeUndefined();
            expect(result.postal_code).toBeUndefined();
            expect(result.city).toBeUndefined();
            expect(result.region).toBeUndefined();
        });

        it("safely handles BigInt values without throwing", () => {
            const result = parseNominatimAddress({
                address: {
                    house_number: BigInt(100) as unknown as string,
                    road: "BigInt Road",
                    postcode: BigInt(21202) as unknown as string,
                },
            } as unknown as INominatimPlace);

            expect(result.street).toBeUndefined();
            expect(result.postal_code).toBeUndefined();
        });

        it("safely handles symbols and functions without throwing", () => {
            const result = parseNominatimAddress({
                place_id: Symbol("id") as unknown as number,
                lat: (() => 39.29) as unknown as string,
                address: {
                    house_number: Symbol("100") as unknown as string,
                    road: (() => "Road") as unknown as string,
                },
            } as unknown as INominatimPlace);

            expect(result.latitude).toBeUndefined();
            expect(result.street).toBeUndefined();
        });
    });

    describe("Fuzz Testing Across 1,200+ Randomized Malformed Payloads", () => {
        const createPrng = (seed: number) => {
            let s = seed >>> 0;
            return () => {
                s = (s + 0x6d2b79f5) >>> 0;
                let t = Math.imul(s ^ (s >>> 15), 1 | s);
                t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            };
        };

        const prng = createPrng(133742);

        const samplePrimitive = (rng: () => number): unknown => {
            const choice = Math.floor(rng() * 18);
            switch (choice) {
                case 0:
                    return undefined;
                case 1:
                    return null;
                case 2:
                    return "";
                case 3:
                    return "   ";
                case 4:
                    return "100";
                case 5:
                    return "Holliday St";
                case 6:
                    return "0x10";
                case 7:
                    return "39.29038foo";
                case 8:
                    return 0;
                case 9:
                    return -0;
                case 10:
                    return 100;
                case 11:
                    return 39.29038;
                case 12:
                    return -76.61219;
                case 13:
                    return NaN;
                case 14:
                    return Infinity;
                case 15:
                    return -Infinity;
                case 16:
                    return true;
                case 17:
                    return false;
                default:
                    return "sample";
            }
        };

        const sampleStructure = (rng: () => number, depth = 0): unknown => {
            if (depth > 2 || rng() < 0.6) {
                return samplePrimitive(rng);
            }
            const structType = Math.floor(rng() * 4);
            if (structType === 0) {
                const len = Math.floor(rng() * 4);
                const arr: unknown[] = [];
                for (let i = 0; i < len; i++) {
                    arr.push(sampleStructure(rng, depth + 1));
                }
                return arr;
            } else if (structType === 1) {
                const obj: Record<string, unknown> = {};
                const keys = ["house_number", "road", "city", "state", "postcode", "lat", "lon", "country", "foo"];
                const count = Math.floor(rng() * 4) + 1;
                for (let i = 0; i < count; i++) {
                    const k = keys[Math.floor(rng() * keys.length)];
                    obj[k] = sampleStructure(rng, depth + 1);
                }
                return obj;
            } else if (structType === 2) {
                const nullObj = Object.create(null);
                nullObj.house_number = samplePrimitive(rng);
                nullObj.road = samplePrimitive(rng);
                return nullObj;
            } else {
                const exotic = Math.floor(rng() * 4);
                if (exotic === 0) return BigInt(42);
                if (exotic === 1) return Symbol("fuzz");
                if (exotic === 2) return new Date();
                return () => "noop";
            }
        };

        it("survives 1,200 randomized malformed payloads without unhandled errors or invalid return shapes", () => {
            for (let i = 0; i < 1200; i++) {
                let payload: unknown;

                if (i === 0) {
                    const circ: any = {};
                    circ.address = circ;
                    circ.self = circ;
                    payload = circ;
                } else if (i === 1) {
                    const circAddr: any = {};
                    circAddr.house_number = "100";
                    circAddr.nested = circAddr;
                    payload = { address: circAddr };
                } else if (i < 50) {
                    payload = samplePrimitive(prng);
                } else {
                    payload = {
                        place_id: samplePrimitive(prng),
                        lat: samplePrimitive(prng),
                        lon: samplePrimitive(prng),
                        display_name: samplePrimitive(prng),
                        address: sampleStructure(prng, 0),
                        boundingbox: sampleStructure(prng, 0),
                        extra_metadata: sampleStructure(prng, 0),
                    };
                }

                let result: any;
                expect(() => {
                    result = parseNominatimAddress(payload as any);
                }).not.toThrow();

                expect(typeof result).toBe("object");
                expect(result).not.toBeNull();

                const isLatitudeValid =
                    result.latitude === undefined ||
                    (typeof result.latitude === "number" &&
                        Number.isFinite(result.latitude) &&
                        result.latitude >= -90 &&
                        result.latitude <= 90);
                expect(isLatitudeValid).toBe(true);

                const isLongitudeValid =
                    result.longitude === undefined ||
                    (typeof result.longitude === "number" &&
                        Number.isFinite(result.longitude) &&
                        result.longitude >= -180 &&
                        result.longitude <= 180);
                expect(isLongitudeValid).toBe(true);

                const areStringsValid = [
                    result.street,
                    result.city,
                    result.region,
                    result.region_code,
                    result.postal_code,
                    result.country,
                ].every((str) => str === undefined || (typeof str === "string" && str.length > 0));
                expect(areStringsValid).toBe(true);
            }
        });
    });
});
