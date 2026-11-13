import { act, renderHook } from "@testing-library/react";
import type { InertiaFormProps } from "@inertiajs/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import {
    type AddressSuggestion,
    buildNominatimUrl,
    isAbortError,
    nominatimPlaceToSuggestion,
    type UseNominatimAddressAutocomplete,
    useNominatimAddressAutocomplete,
} from "app/frontend/hooks/useNominatimAddressAutocomplete";
import type {
    AddressSuggestion as LegacyAddressSuggestion,
    UseAddressAutocomplete as LegacyUseAddressAutocomplete,
} from "app/frontend/hooks/useAddressAutocomplete";
import type { INominatimPlace } from "app/frontend/sway_utils/parseNominatimAddress";

interface ITestAddressForm extends Partial<sway.IAddress> {
    is_voter_registration_address_confirmed?: boolean;
    place_types?: string[];
    [key: string]: unknown;
}

const DEBOUNCE_MS = 1000;

const BALTIMORE_LOCALE: sway.ISwayLocale = {
    id: 1,
    name: "baltimore-maryland-united_states",
    city: "baltimore",
    region_code: "MD",
    region_name: "Maryland",
    country: "united_states",
    icon_url: "public/images/flags/baltimore-maryland-united_states.svg",
    time_zone: "America/New_York",
    current_session_start_date: "2024-12-05",
    default_bill_chamber: null,
    bill_chambers: null,
    nominatim_viewbox: "-76.7114,39.3720,-76.5297,39.1972",
    nominatim_bounded: true,
    nominatim_country_codes: "us",
};

const CONGRESS_LOCALE: sway.ISwayLocale = {
    id: 2,
    name: "congress-congress-united_states",
    city: "congress",
    region_code: "",
    region_name: "congress",
    country: "united_states",
    icon_url: "public/images/flags/congress-congress-united_states.svg",
    time_zone: "America/New_York",
    current_session_start_date: "2025-01-03",
    default_bill_chamber: null,
    bill_chambers: null,
    nominatim_viewbox: null,
    nominatim_bounded: false,
    nominatim_country_codes: "us",
};

const buildMockForm = (initialData: Partial<ITestAddressForm> = {}): InertiaFormProps<ITestAddressForm> => {
    const data: ITestAddressForm = { ...initialData };
    const setDataMock = vi.fn<((key: string, value: unknown) => void) & ((data: ITestAddressForm) => void)>(
        (keyOrData: string | ITestAddressForm, value?: unknown) => {
            if (typeof keyOrData === "string") {
                (data as Record<string, unknown>)[keyOrData] = value;
            } else {
                Object.assign(data, keyOrData);
            }
        },
    );

    return {
        data,
        errors: {},
        hasErrors: false,
        processing: false,
        wasSuccessful: false,
        recentlySuccessful: false,
        setData: setDataMock,
        transform: vi.fn<() => unknown>(),
        reset: vi.fn<() => void>(),
        clearErrors: vi.fn<() => void>(),
        setError: vi.fn<() => void>(),
        post: vi.fn<() => void>(),
        put: vi.fn<() => void>(),
        patch: vi.fn<() => void>(),
        delete: vi.fn<() => void>(),
        get: vi.fn<() => void>(),
        progress: null,
    } as unknown as InertiaFormProps<ITestAddressForm>;
};

const createMockPlace = (overrides: Partial<INominatimPlace> = {}): INominatimPlace => ({
    place_id: 100149,
    osm_type: "node",
    osm_id: 107775,
    lat: "39.29038",
    lon: "-76.61219",
    display_name: "100 Holliday Street, Downtown, Baltimore, Maryland, 21202, United States",
    boundingbox: ["39.28038", "39.30038", "-76.62219", "-76.60219"],
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
    ...overrides,
});

const createFetchResponse = (body: unknown, status = 200, statusText = "OK"): Response =>
    ({
        ok: status >= 200 && status < 300,
        status,
        statusText,
        json: async () => body,
        headers: new Headers({ "Content-Type": "application/json" }),
    }) as unknown as Response;

describe("useNominatimAddressAutocomplete", () => {
    let fetchMock: ReturnType<typeof vi.fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>>;

    const getRequestedUrl = (callIndex = 0): string => {
        const callArg = fetchMock.mock.calls[callIndex]?.[0];
        if (typeof callArg === "string") return callArg;
        if (callArg instanceof URL) return callArg.toString();
        return "";
    };

    beforeEach(() => {
        vi.useFakeTimers();
        fetchMock = vi
            .fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>()
            .mockResolvedValue(createFetchResponse([createMockPlace()]));
        vi.stubGlobal("fetch", fetchMock);
    });

    afterEach(() => {
        vi.useRealTimers();
        vi.unstubAllGlobals();
    });

    describe("nominatimPlaceToSuggestion", () => {
        it("formats complete place into AddressSuggestion with house_number and road as main_text", () => {
            const place = createMockPlace();
            const suggestion = nominatimPlaceToSuggestion(place);

            expect(suggestion).toEqual({
                place_id: "100149",
                description: "100 Holliday Street, Downtown, Baltimore, Maryland, 21202, United States",
                structured_formatting: {
                    main_text: "100 Holliday Street",
                    secondary_text: "Downtown, Baltimore, Maryland, 21202, United States",
                },
            });
        });

        it("formats place with road only (no house_number) using road as main_text", () => {
            const place = createMockPlace({
                display_name: "Holliday Street, Baltimore, Maryland, 21202, United States",
                address: {
                    road: "Holliday Street",
                    city: "Baltimore",
                    state: "Maryland",
                    country: "United States",
                },
            });
            const suggestion = nominatimPlaceToSuggestion(place);

            expect(suggestion.structured_formatting.main_text).toBe("Holliday Street");
            expect(suggestion.structured_formatting.secondary_text).toContain("Baltimore, Maryland");
        });

        it("falls back to first comma-separated segment of display_name when address is absent", () => {
            const place: INominatimPlace = {
                place_id: "osm-999",
                display_name: "City Hall, Holliday Street, Baltimore, Maryland",
            };
            const suggestion = nominatimPlaceToSuggestion(place);

            expect(suggestion.structured_formatting.main_text).toBe("City Hall");
            expect(suggestion.structured_formatting.secondary_text).toBe("Holliday Street, Baltimore, Maryland");
        });

        it("handles numeric or string place_id correctly", () => {
            const numPlace = createMockPlace({ place_id: 12345 });
            expect(nominatimPlaceToSuggestion(numPlace).place_id).toBe("12345");

            const strPlace = createMockPlace({ place_id: "W12345" });
            expect(nominatimPlaceToSuggestion(strPlace).place_id).toBe("W12345");
        });

        it("safely handles place with missing or empty display_name", () => {
            const emptyPlace: INominatimPlace = {
                place_id: 1,
                display_name: "",
            };
            const suggestion = nominatimPlaceToSuggestion(emptyPlace);

            expect(suggestion.place_id).toBe("1");
            expect(suggestion.description).toBe("");
            expect(suggestion.structured_formatting.main_text).toBe("");
            expect(suggestion.structured_formatting.secondary_text).toBe("");
        });
    });

    describe("Initial Hook State & Pre-population", () => {
        it("initializes with empty value, status 'IDLE', empty suggestions, and loading false when form is empty", () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            expect(result.current.value).toBe("");
            expect(result.current.status).toBe("IDLE");
            expect(result.current.suggestions).toEqual([]);
            expect(result.current.loading).toBe(false);
        });

        it("initializes value from pre-existing form address when street, city, region_code, and postal_code are present", () => {
            const form = buildMockForm({
                street: "100 Holliday St",
                city: "Baltimore",
                region_code: "MD",
                postal_code: "21202",
            });
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            expect(result.current.value).toBe("100 Holliday St Baltimore, MD, 21202");
        });

        it("leaves value empty if form address is partial or missing street/city", () => {
            const form = buildMockForm({
                city: "Baltimore",
            });
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            expect(result.current.value).toBe("");
        });
    });

    describe("Typed text", () => {
        it("handleInput writes the typed text to the form under typed_address", () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            expect(form.setData).toHaveBeenCalledWith("typed_address", "100 Holliday");
        });

        it("shows the form's typed_address as the box text", () => {
            const form = buildMockForm({ typed_address: "5 Elm St" });
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            expect(result.current.value).toBe("5 Elm St");
        });

        it("shows a typed_address the form receives after the first render", () => {
            const form = buildMockForm();
            const { result, rerender } = renderHook(() => useNominatimAddressAutocomplete(form));

            form.data.typed_address = "5 Elm St";
            rerender();

            expect(result.current.value).toBe("5 Elm St");
        });
    });

    describe("Selected address", () => {
        const SELECTED_FIELDS = [
            "street",
            "city",
            "region",
            "region_code",
            "postal_code",
            "country",
            "latitude",
            "longitude",
            "place_types",
        ];

        const typeText = (result: { current: ReturnType<typeof useNominatimAddressAutocomplete> }, text: string) => {
            act(() => {
                result.current.handleInput({
                    target: { value: text },
                } as React.ChangeEvent<HTMLInputElement>);
            });
        };

        const searchAndSelect = async (
            result: { current: ReturnType<typeof useNominatimAddressAutocomplete> },
            place: INominatimPlace,
        ) => {
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));
            typeText(result, "100 Holliday");
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });
            act(() => {
                result.current.handleSelect(result.current.suggestions[0])();
            });
        };

        it("handleInput after a selection clears every selected field from the form", async () => {
            const form = buildMockForm();
            const { result, rerender } = renderHook(() => useNominatimAddressAutocomplete(form));
            await searchAndSelect(result, createMockPlace());
            expect(form.data).toMatchObject({ street: "100 Holliday Street", postal_code: "21202" });

            typeText(result, "200 Other Street");
            rerender();

            SELECTED_FIELDS.forEach((field) => {
                expect((form.data as Record<string, unknown>)[field]).toBeUndefined();
            });
            expect(result.current.value).toBe("200 Other Street");
            expect((form.data as Record<string, unknown>).typed_address).toBe("200 Other Street");
        });

        it("handleInput before any selection leaves the form without selected fields", () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            typeText(result, "100 Holl");

            SELECTED_FIELDS.forEach((field) => {
                expect((form.data as Record<string, unknown>)[field]).toBeUndefined();
            });
            expect((form.data as Record<string, unknown>).typed_address).toBe("100 Holl");
        });

        it("handleInput clears an address that was already on the form when the user edits the text", () => {
            const form = buildMockForm({
                street: "100 Holliday St",
                city: "Baltimore",
                region_code: "MD",
                postal_code: "21202",
            });
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            typeText(result, "5 Elm St");

            expect(form.data.street).toBeUndefined();
            expect(form.data.postal_code).toBeUndefined();
        });

        it("a selection without a postcode does not keep the postal_code of an earlier address", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));
            const placeWithoutPostcode = createMockPlace({
                place_id: 200,
                lat: "39.5",
                lon: "-76.5",
                address: { road: "Rural Road", city: "Towson", state: "Maryland", "ISO3166-2-lvl4": "US-MD" },
            });
            fetchMock.mockResolvedValueOnce(createFetchResponse([placeWithoutPostcode]));
            typeText(result, "Rural Road");
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });
            Object.assign(form.data, { street: "100 Holliday Street", city: "Baltimore", postal_code: "21202" });

            act(() => {
                result.current.handleSelect(result.current.suggestions[0])();
            });

            const data = form.data as Record<string, unknown>;
            expect(data.postal_code).toBeUndefined();
            expect(data.street).toBeUndefined();
            expect(data.city).toBe("Towson");
            expect(data.latitude).toBe(39.5);
        });

        it("handleSelect records the text the box shows as typed_address", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));
            await searchAndSelect(result, createMockPlace());

            expect((form.data as Record<string, unknown>).typed_address).toBe(result.current.value);
        });
    });

    describe("Debounce Timing & Rate Limiting", () => {
        it("does NOT trigger fetch before 1000ms debounce threshold expires (e.g. at 500ms or 999ms)", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(500);
            });
            expect(fetchMock).not.toHaveBeenCalled();

            await act(async () => {
                await vi.advanceTimersByTimeAsync(499);
            });
            expect(fetchMock).not.toHaveBeenCalled();
        });

        it("triggers exactly one fetch once debounce threshold of >= 1000ms is reached", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
        });

        it("collapses rapid keystrokes into a single fetch after typing pauses", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            const keystrokes = ["1", "10", "100", "100 ", "100 H", "100 Holliday"];
            for (const text of keystrokes) {
                act(() => {
                    result.current.handleInput({
                        target: { value: text },
                    } as React.ChangeEvent<HTMLInputElement>);
                });
                await act(async () => {
                    await vi.advanceTimersByTimeAsync(250);
                });
            }

            expect(fetchMock).not.toHaveBeenCalled();

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const requestedUrl = getRequestedUrl();
            expect(decodeURIComponent(requestedUrl)).toContain("q=100 Holliday");
        });

        it("clearing input immediately cancels pending debounce timer without firing fetch", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(400);
            });

            act(() => {
                result.current.handleInput({
                    target: { value: "" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(2000);
            });

            expect(fetchMock).not.toHaveBeenCalled();
            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("IDLE");
        });

        it("whitespace-only input does not trigger fetch and resets suggestions", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "    " },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(1500);
            });

            expect(fetchMock).not.toHaveBeenCalled();
            expect(result.current.suggestions).toEqual([]);
        });
    });

    describe("Request Headers & Policy Verification", () => {
        it("sends an identifiable User-Agent header in the request options", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const requestInit = fetchMock.mock.calls[0][1] as RequestInit;
            expect(requestInit).toBeDefined();

            const headers = (requestInit.headers ?? {}) as Record<string, string>;
            const userAgent = headers["User-Agent"] || (headers as unknown as Headers).get?.("User-Agent");
            expect(userAgent).toBeDefined();
            expect(String(userAgent).toLowerCase()).toContain("sway");
        });

        it("sends Accept: application/json header", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const requestInit = fetchMock.mock.calls[0][1] as RequestInit;
            const headers = (requestInit.headers ?? {}) as Record<string, string>;
            const accept = headers["Accept"] || (headers as unknown as Headers).get?.("Accept");
            expect(accept).toContain("application/json");
        });
    });

    describe("Query Parameters & Geographic Locale Boundaries", () => {
        it("constructs the base search URL with q, format=jsonv2, addressdetails=1, and limit=5", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const requestedUrl = new URL(getRequestedUrl());
            expect(requestedUrl.pathname).toBe("/addresses/autocomplete");
            expect(requestedUrl.searchParams.get("format")).toBe("jsonv2");
            expect(requestedUrl.searchParams.get("addressdetails")).toBe("1");
            expect(requestedUrl.searchParams.get("limit")).toBe("5");
            expect(requestedUrl.searchParams.get("q")).toBe("100 Holliday");
        });

        it("includes viewbox and bounded=1 when ISwayLocale has nominatim_viewbox and nominatim_bounded=true (e.g. Baltimore)", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, BALTIMORE_LOCALE));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const requestedUrl = new URL(getRequestedUrl());
            expect(requestedUrl.searchParams.get("viewbox")).toBe("-76.7114,39.3720,-76.5297,39.1972");
            expect(requestedUrl.searchParams.get("bounded")).toBe("1");
            expect(requestedUrl.searchParams.get("countrycodes")).toBe("us");
        });

        it("omits viewbox and sets bounded=0 (or omits) when ISwayLocale has null nominatim_viewbox (e.g. Congress)", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, CONGRESS_LOCALE));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const requestedUrl = new URL(getRequestedUrl());
            expect(requestedUrl.searchParams.has("viewbox")).toBe(false);
            const bounded = requestedUrl.searchParams.get("bounded");
            expect(bounded === null || bounded === "0").toBe(true);
            expect(requestedUrl.searchParams.get("countrycodes")).toBe("us");
        });

        it("omits countrycodes if locale nominatim_country_codes is null", async () => {
            const customLocale: sway.ISwayLocale = {
                ...CONGRESS_LOCALE,
                nominatim_country_codes: null,
            };
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, customLocale));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const requestedUrl = new URL(getRequestedUrl());
            expect(requestedUrl.searchParams.has("countrycodes")).toBe(false);
        });

        it("handles undefined or null locale gracefully without throwing and applies default search", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, null));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const requestedUrl = new URL(getRequestedUrl());
            expect(requestedUrl.searchParams.get("q")).toBe("100 Holliday");
            expect(requestedUrl.searchParams.has("viewbox")).toBe(false);
        });

        it("properly URL-encodes special characters and spaces in q parameter", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 N & S St #4?" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const requestedUrl = new URL(getRequestedUrl());
            expect(requestedUrl.searchParams.get("q")).toBe("100 N & S St #4?");
        });
    });

    describe("Response Parsing, Suggestions & Status Updates", () => {
        it("updates suggestions, sets status='OK', and resets loading on successful search", async () => {
            const place1 = createMockPlace({ place_id: 101, display_name: "100 Holliday St, Baltimore, MD" });
            const place2 = createMockPlace({ place_id: 102, display_name: "200 Holliday St, Baltimore, MD" });
            fetchMock.mockResolvedValueOnce(createFetchResponse([place1, place2]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.suggestions).toHaveLength(2);
            expect(result.current.suggestions[0].place_id).toBe("101");
            expect(result.current.suggestions[1].place_id).toBe("102");
            expect(result.current.status).toBe("OK");
            expect(result.current.loading).toBe(false);
        });

        it("sets status='ZERO_RESULTS' and suggestions=[] when Nominatim returns an empty array", async () => {
            fetchMock.mockResolvedValueOnce(createFetchResponse([]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Nonexistent Address 99999" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("ZERO_RESULTS");
            expect(result.current.loading).toBe(false);
        });

        it("manages loading state correctly throughout fetch lifecycle", async () => {
            let resolveFetch!: (res: Response) => void;
            const deferredPromise = new Promise<Response>((resolve) => {
                resolveFetch = resolve;
            });
            fetchMock.mockReturnValueOnce(deferredPromise);

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            expect(result.current.loading).toBe(false);

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.loading).toBe(true);
            expect(setLoadingMock).toHaveBeenCalledWith(true);

            await act(async () => {
                resolveFetch(createFetchResponse([createMockPlace()]));
            });

            expect(result.current.loading).toBe(false);
            expect(setLoadingMock).toHaveBeenCalledWith(false);
        });
    });

    describe("Suggestion Selection & Form Population", () => {
        it("handleSelect updates hook input value to selected suggestion description", async () => {
            const place = createMockPlace({ display_name: "100 Holliday Street, Baltimore, MD" });
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const pickedSuggestion = result.current.suggestions[0];
            act(() => {
                result.current.handleSelect(pickedSuggestion)();
            });

            expect(result.current.value).toBe(pickedSuggestion.description);
        });

        it("handleSelect clears suggestions and resets status", async () => {
            const place = createMockPlace();
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.suggestions).toHaveLength(1);

            act(() => {
                result.current.handleSelect(result.current.suggestions[0])();
            });

            expect(result.current.suggestions).toEqual([]);
        });

        it("handleSelect invokes parseNominatimAddress and calls form.setData with all parsed fields", async () => {
            const place = createMockPlace({
                lat: "39.29038",
                lon: "-76.61219",
                address: {
                    house_number: "100",
                    road: "Holliday Street",
                    city: "Baltimore",
                    state: "Maryland",
                    "ISO3166-2-lvl4": "US-MD",
                    postcode: "21202",
                    country: "United States",
                    country_code: "us",
                },
            });
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const picked = result.current.suggestions[0];
            act(() => {
                result.current.handleSelect(picked)();
            });

            expect(form.setData).toHaveBeenCalledWith("street", "100 Holliday Street");
            expect(form.setData).toHaveBeenCalledWith("city", "Baltimore");
            expect(form.setData).toHaveBeenCalledWith("region", "Maryland");
            expect(form.setData).toHaveBeenCalledWith("region_code", "MD");
            expect(form.setData).toHaveBeenCalledWith("postal_code", "21202");
            expect(form.setData).toHaveBeenCalledWith("country", "United States");
            expect(form.setData).toHaveBeenCalledWith("latitude", 39.29038);
            expect(form.setData).toHaveBeenCalledWith("longitude", -76.61219);
        });

        it("handleSelect manages external setLoading lifecycle (true at start, false on finish)", async () => {
            const place = createMockPlace();
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            setLoadingMock.mockClear();

            act(() => {
                result.current.handleSelect(result.current.suggestions[0])();
            });

            expect(setLoadingMock).toHaveBeenCalledWith(true);
            expect(setLoadingMock).toHaveBeenCalledWith(false);
        });

        it("handleSelect operates safely when setLoading is omitted", async () => {
            const place = createMockPlace();
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(() => {
                act(() => {
                    result.current.handleSelect(result.current.suggestions[0])();
                });
            }).not.toThrow();
        });

        it("handleSelect cancels pending debounced searches so subsequent timer triggers do not overwrite selected address", async () => {
            const place = createMockPlace();
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const picked = result.current.suggestions[0];
            fetchMock.mockClear();

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday Str" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            act(() => {
                result.current.handleSelect(picked)();
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS * 2);
            });

            expect(fetchMock).not.toHaveBeenCalled();
        });
    });

    describe("Network Failures, HTTP Errors & Race Conditions", () => {
        it("sets status='ERROR' and loading=false when fetch throws network error", async () => {
            fetchMock.mockRejectedValueOnce(new TypeError("Failed to fetch"));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("sets status='ERROR' and loading=false on HTTP 500 Internal Server Error", async () => {
            fetchMock.mockResolvedValueOnce(createFetchResponse(null, 500, "Internal Server Error"));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
        });

        it("sets status='ERROR' and loading=false on HTTP 429 Too Many Requests (rate limiting)", async () => {
            fetchMock.mockResolvedValueOnce(
                createFetchResponse({ error: "Bandwidth limit exceeded" }, 429, "Too Many Requests"),
            );

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
        });

        it("handles malformed non-JSON response gracefully without throwing", async () => {
            fetchMock.mockResolvedValueOnce({
                ok: true,
                status: 200,
                statusText: "OK",
                json: async () => {
                    throw new SyntaxError("Unexpected token '<' in JSON at position 0");
                },
                headers: new Headers({ "Content-Type": "text/html" }),
            } as unknown as Response);

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
        });

        it("discards out-of-order stale fetch responses when newer keystroke occurs (race condition prevention)", async () => {
            let resolveRequest1!: (res: Response) => void;
            const promise1 = new Promise<Response>((resolve) => {
                resolveRequest1 = resolve;
            });
            const place1 = createMockPlace({ place_id: 111, display_name: "Stale Place 111" });
            const place2 = createMockPlace({ place_id: 222, display_name: "Fresh Place 222" });

            fetchMock.mockReturnValueOnce(promise1);
            fetchMock.mockResolvedValueOnce(createFetchResponse([place2]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Term 1" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            act(() => {
                result.current.handleInput({
                    target: { value: "Term 2" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.suggestions[0].place_id).toBe("222");

            await act(async () => {
                resolveRequest1(createFetchResponse([place1]));
            });

            expect(result.current.suggestions[0].place_id).toBe("222");
        });

        it("cleans up pending timers and handles unmount safely", async () => {
            const form = buildMockForm();
            const { result, unmount } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            unmount();

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS * 2);
            });

            expect(fetchMock).not.toHaveBeenCalled();
        });

        it("silently suppresses DOMException AbortError without transitioning to ERROR status", async () => {
            fetchMock.mockRejectedValueOnce(new DOMException("The user aborted a request.", "AbortError"));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).not.toBe("ERROR");
            expect(result.current.status).toBe("IDLE");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("silently suppresses Error instance with name='AbortError' without transitioning to ERROR status", async () => {
            const error = new Error("The user aborted a request.");
            error.name = "AbortError";
            fetchMock.mockRejectedValueOnce(error);

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).not.toBe("ERROR");
            expect(result.current.status).toBe("IDLE");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("silently suppresses cross-realm duck-typed AbortError without transitioning to ERROR status", async () => {
            fetchMock.mockRejectedValueOnce({
                name: "AbortError",
                message: "The user aborted a request.",
            });

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).not.toBe("ERROR");
            expect(result.current.status).toBe("IDLE");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });
    });

    describe("isAbortError Helper Unit Tests", () => {
        it("identifies native DOMException with AbortError name", () => {
            const err = new DOMException("Aborted", "AbortError");
            expect(isAbortError(err)).toBe(true);
        });

        it("identifies Error instance with AbortError name", () => {
            const err = new Error("Aborted");
            err.name = "AbortError";
            expect(isAbortError(err)).toBe(true);
        });

        it("identifies duck-typed object with AbortError name", () => {
            expect(isAbortError({ name: "AbortError" })).toBe(true);
        });

        it("returns false for non-abort DOMException (e.g. TimeoutError)", () => {
            const err = new DOMException("Timeout", "TimeoutError");
            expect(isAbortError(err)).toBe(false);
        });

        it("returns false for regular Error", () => {
            expect(isAbortError(new Error("Generic"))).toBe(false);
        });

        it("returns false for null, undefined, and non-error primitives", () => {
            expect(isAbortError(null)).toBe(false);
            expect(isAbortError(undefined)).toBe(false);
            expect(isAbortError("AbortError")).toBe(false);
            expect(isAbortError(123)).toBe(false);
        });
    });

    describe("Manual Helper Controls", () => {
        it("clearSuggestions resets suggestions to [] and status to ''", async () => {
            const place = createMockPlace();
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.suggestions).toHaveLength(1);

            act(() => {
                result.current.clearSuggestions();
            });

            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("");
        });
    });

    describe("Adversarial Boundary Injection & Contract Parity Challenge", () => {
        it("injects exact Annapolis locale boundaries: viewbox=-76.5450,39.0200,-76.4650,38.9400&bounded=1&countrycodes=us", async () => {
            const annapolisLocale: sway.ISwayLocale = {
                ...BALTIMORE_LOCALE,
                name: "annapolis-maryland-united_states",
                city: "annapolis",
                nominatim_viewbox: "-76.5450,39.0200,-76.4650,38.9400",
                nominatim_bounded: true,
                nominatim_country_codes: "us",
            };
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, annapolisLocale));

            act(() => {
                result.current.handleInput({
                    target: { value: "State Circle" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const url = new URL(getRequestedUrl());
            expect(url.searchParams.get("viewbox")).toBe("-76.5450,39.0200,-76.4650,38.9400");
            expect(url.searchParams.get("bounded")).toBe("1");
            expect(url.searchParams.get("countrycodes")).toBe("us");
        });

        it("injects exact Maryland statewide boundaries: viewbox=-79.4877,39.7230,-75.0489,37.9117&bounded=1&countrycodes=us", async () => {
            const marylandLocale: sway.ISwayLocale = {
                ...BALTIMORE_LOCALE,
                name: "maryland-maryland-united_states",
                city: "maryland",
                nominatim_viewbox: "-79.4877,39.7230,-75.0489,37.9117",
                nominatim_bounded: true,
                nominatim_country_codes: "us",
            };
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, marylandLocale));

            act(() => {
                result.current.handleInput({
                    target: { value: "Rockville Pike" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const url = new URL(getRequestedUrl());
            expect(url.searchParams.get("viewbox")).toBe("-79.4877,39.7230,-75.0489,37.9117");
            expect(url.searchParams.get("bounded")).toBe("1");
            expect(url.searchParams.get("countrycodes")).toBe("us");
        });

        it("handles soft bounding: viewbox present with nominatim_bounded=false sets bounded=0", async () => {
            const softLocale: sway.ISwayLocale = {
                ...BALTIMORE_LOCALE,
                nominatim_bounded: false,
            };
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, softLocale));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const url = new URL(getRequestedUrl());
            expect(url.searchParams.get("viewbox")).toBe("-76.7114,39.3720,-76.5297,39.1972");
            expect(url.searchParams.get("bounded")).toBe("0");
            expect(url.searchParams.get("countrycodes")).toBe("us");
        });

        it("avoids injecting bounded when nominatim_viewbox is null or empty even if nominatim_bounded is true", async () => {
            const anomalyLocale: sway.ISwayLocale = {
                ...BALTIMORE_LOCALE,
                nominatim_viewbox: null,
                nominatim_bounded: true,
            };
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, anomalyLocale));

            act(() => {
                result.current.handleInput({
                    target: { value: "Main St" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const url = new URL(getRequestedUrl());
            expect(url.searchParams.has("viewbox")).toBe(false);
            expect(url.searchParams.has("bounded")).toBe(false);
        });

        it("converts uppercase or mixed-case country codes to lowercase", async () => {
            const upperLocale: sway.ISwayLocale = {
                ...CONGRESS_LOCALE,
                nominatim_country_codes: "US,CA",
            };
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, upperLocale));

            act(() => {
                result.current.handleInput({
                    target: { value: "Main St" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const url = new URL(getRequestedUrl());
            expect(url.searchParams.get("countrycodes")).toBe("us,ca");
        });

        it("dynamically adapts when locale prop changes across renders", async () => {
            const form = buildMockForm();
            let currentLocale: sway.ISwayLocale = BALTIMORE_LOCALE;

            const { result, rerender } = renderHook(
                ({ locale }) => useNominatimAddressAutocomplete(form, undefined, locale),
                { initialProps: { locale: currentLocale } },
            );

            act(() => {
                result.current.handleInput({
                    target: { value: "Query 1" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const url1 = new URL(getRequestedUrl(0));
            expect(url1.searchParams.get("viewbox")).toBe(BALTIMORE_LOCALE.nominatim_viewbox);
            expect(url1.searchParams.get("bounded")).toBe("1");

            currentLocale = CONGRESS_LOCALE;
            rerender({ locale: currentLocale });

            act(() => {
                result.current.handleInput({
                    target: { value: "Query 2" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const url2 = new URL(getRequestedUrl(1));
            expect(url2.searchParams.has("viewbox")).toBe(false);
            expect(url2.searchParams.get("q")).toBe("Query 2");
        });

        it("returns an object satisfying UseAddressAutocomplete contract keys and types", () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            const returned = result.current;
            const expectedKeys: (keyof UseNominatimAddressAutocomplete)[] = [
                "value",
                "status",
                "suggestions",
                "loading",
                "handleInput",
                "handleSelect",
                "clearSuggestions",
            ];
            for (const key of expectedKeys) {
                expect(returned).toHaveProperty(key);
            }

            expect(typeof returned.value).toBe("string");
            expect(typeof returned.status).toBe("string");
            expect(Array.isArray(returned.suggestions)).toBe(true);
            expect(typeof returned.loading).toBe("boolean");
            expect(typeof returned.handleInput).toBe("function");
            expect(typeof returned.handleSelect).toBe("function");
            expect(typeof returned.clearSuggestions).toBe("function");

            const legacyAssignmentCheck: LegacyUseAddressAutocomplete = returned;
            expect(legacyAssignmentCheck).toBeDefined();
        });

        it("produces AddressSuggestion compatible with LegacyAddressSuggestion", () => {
            const place = createMockPlace({
                place_id: "osm-42",
                display_name: "42 Wallaby Way, Sydney",
                address: {
                    house_number: "42",
                    road: "Wallaby Way",
                    city: "Sydney",
                },
            });
            const suggestion: AddressSuggestion = nominatimPlaceToSuggestion(place);

            expect(suggestion).toHaveProperty("place_id");
            expect(suggestion).toHaveProperty("description");
            expect(suggestion).toHaveProperty("structured_formatting");
            expect(suggestion.structured_formatting).toHaveProperty("main_text");
            expect(suggestion.structured_formatting).toHaveProperty("secondary_text");

            const legacySuggestion: LegacyAddressSuggestion = suggestion;
            expect(legacySuggestion.place_id).toBe("osm-42");
            expect(legacySuggestion.structured_formatting.main_text).toBe("42 Wallaby Way");
        });

        it("simulates combobox isOpen lifecycle: false -> false -> true -> false", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            let isOpen = result.current.status === "OK" && result.current.suggestions.length > 0;
            expect(isOpen).toBe(false);

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            isOpen = result.current.status === "OK" && result.current.suggestions.length > 0;
            expect(isOpen).toBe(false);

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });
            isOpen = result.current.status === "OK" && result.current.suggestions.length > 0;
            expect(isOpen).toBe(true);

            act(() => {
                result.current.clearSuggestions();
            });
            isOpen = result.current.status === "OK" && result.current.suggestions.length > 0;
            expect(isOpen).toBe(false);
            expect(result.current.status).toBe("");
        });

        it("populates place_types on form matching legacy behavior", async () => {
            const place = createMockPlace({
                type: "administrative",
                class: "boundary",
            });
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            const suggestion = result.current.suggestions[0];
            act(() => {
                result.current.handleSelect(suggestion)();
            });

            expect(form.setData).toHaveBeenCalledWith("place_types", ["administrative", "boundary"]);
        });

        it("handles selection using suggestion.raw_place when present", async () => {
            const customPlace = createMockPlace({
                place_id: "synthetic-999",
                lat: "38.9072",
                lon: "-77.0369",
                display_name: "1600 Pennsylvania Ave NW, Washington, DC",
                address: {
                    house_number: "1600",
                    road: "Pennsylvania Ave NW",
                    city: "Washington",
                    state: "District of Columbia",
                    "ISO3166-2-lvl4": "US-DC",
                    postcode: "20500",
                    country: "United States",
                    country_code: "us",
                },
            });

            const suggestionWithRaw: AddressSuggestion = {
                place_id: "synthetic-999",
                description: "1600 Pennsylvania Ave NW, Washington, DC",
                structured_formatting: {
                    main_text: "1600 Pennsylvania Ave NW",
                    secondary_text: "Washington, DC",
                },
                raw_place: customPlace,
            };

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleSelect(suggestionWithRaw)();
            });

            expect(form.setData).toHaveBeenCalledWith("street", "1600 Pennsylvania Ave NW");
            expect(form.setData).toHaveBeenCalledWith("city", "Washington");
            expect(form.setData).toHaveBeenCalledWith("region_code", "DC");
            expect(form.setData).toHaveBeenCalledWith("postal_code", "20500");
            expect(form.setData).toHaveBeenCalledWith("latitude", 38.9072);
            expect(form.setData).toHaveBeenCalledWith("longitude", -77.0369);
        });

        it("gracefully tolerates handleSelect with unknown suggestion not found in places cache", () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            const orphanSuggestion: AddressSuggestion = {
                place_id: "unknown-id",
                description: "Nonexistent Street, Baltimore, MD",
                structured_formatting: {
                    main_text: "Nonexistent Street",
                    secondary_text: "Baltimore, MD",
                },
            };

            expect(() => {
                act(() => {
                    result.current.handleSelect(orphanSuggestion)();
                });
            }).not.toThrow();

            expect(result.current.value).toBe("Nonexistent Street, Baltimore, MD");
            expect(result.current.suggestions).toEqual([]);
        });

        it("encodes query with literal '+' character as %2B rather than replacing with space", () => {
            const url = buildNominatimUrl("100+200 Main St", BALTIMORE_LOCALE);
            expect(url).toContain("q=100%2B200%20Main%20St");
        });

        it("filters out null, undefined, and primitive items in json array without crashing", async () => {
            const malformedArray = [
                null,
                undefined,
                42,
                "string",
                createMockPlace({ place_id: "valid-1", display_name: "Valid Place 1" }),
            ];
            fetchMock.mockResolvedValueOnce(createFetchResponse(malformedArray));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Test" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("OK");
            expect(result.current.suggestions).toHaveLength(1);
            expect(result.current.suggestions[0].place_id).toBe("valid-1");
        });

        it("safely handles empty object item in json array without throwing", async () => {
            const malformedArray = [{}, createMockPlace({ place_id: "valid-1", display_name: "Valid Place 1" })];
            fetchMock.mockResolvedValueOnce(createFetchResponse(malformedArray));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Test" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("OK");
            expect(result.current.suggestions).toHaveLength(2);
            expect(result.current.suggestions[0].place_id).toBe("");
            expect(result.current.suggestions[1].place_id).toBe("valid-1");
        });

        it("handles places where address object is missing or null", async () => {
            const placeWithoutAddress: INominatimPlace = {
                place_id: "no-addr-1",
                display_name: "Memorial Stadium, Baltimore, MD, USA",
                lat: "39.329",
                lon: "-76.600",
            };
            fetchMock.mockResolvedValueOnce(createFetchResponse([placeWithoutAddress]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Memorial" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.suggestions).toHaveLength(1);
            const suggestion = result.current.suggestions[0];
            expect(suggestion.place_id).toBe("no-addr-1");
            expect(suggestion.structured_formatting.main_text).toBe("Memorial Stadium");

            act(() => {
                result.current.handleSelect(suggestion)();
            });
            expect(form.setData).toHaveBeenCalledWith("latitude", 39.329);
            expect(form.setData).toHaveBeenCalledWith("longitude", -76.6);
        });

        it("handles HTTP 403 Forbidden / Nominatim Block gracefully", async () => {
            fetchMock.mockResolvedValueOnce(createFetchResponse("Blocked", 403, "Forbidden"));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.suggestions).toEqual([]);
            expect(result.current.loading).toBe(false);
        });

        it("handles HTTP 502 Bad Gateway / Upstream failure gracefully", async () => {
            fetchMock.mockResolvedValueOnce(createFetchResponse(null, 502, "Bad Gateway"));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.suggestions).toEqual([]);
            expect(result.current.loading).toBe(false);
        });
    });

    describe("Adversarial Concurrency & In-Flight Cancellation Regressions", () => {
        it("clearing input while request is in flight aborts fetch, disregards late response, and resets loading to false", async () => {
            let resolveFetch!: (res: Response) => void;
            const pendingPromise = new Promise<Response>((resolve) => {
                resolveFetch = resolve;
            });
            fetchMock.mockReturnValueOnce(pendingPromise);

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            expect(result.current.loading).toBe(true);
            expect(setLoadingMock).toHaveBeenLastCalledWith(true);

            act(() => {
                result.current.handleInput({
                    target: { value: "" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("IDLE");
            expect(result.current.loading).toBe(false);
            expect(setLoadingMock).toHaveBeenLastCalledWith(false);

            const latePlace = createMockPlace({ place_id: 9999, display_name: "Late Arriving Street" });
            await act(async () => {
                resolveFetch(createFetchResponse([latePlace]));
            });

            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("IDLE");
            expect(result.current.loading).toBe(false);
        });

        it("calling clearSuggestions while request is in flight cancels in-flight response, prevents suggestion resurrection, and resets loading", async () => {
            let resolveFetch!: (res: Response) => void;
            const pendingPromise = new Promise<Response>((resolve) => {
                resolveFetch = resolve;
            });
            fetchMock.mockReturnValueOnce(pendingPromise);

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            expect(result.current.loading).toBe(true);
            expect(setLoadingMock).toHaveBeenLastCalledWith(true);

            act(() => {
                result.current.clearSuggestions();
            });

            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("");
            expect(result.current.loading).toBe(false);
            expect(setLoadingMock).toHaveBeenLastCalledWith(false);

            const latePlace = createMockPlace({ place_id: 888, display_name: "Cleared Place" });
            await act(async () => {
                resolveFetch(createFetchResponse([latePlace]));
            });

            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).not.toBe("OK");
            expect(result.current.status).toBe("");
            expect(result.current.loading).toBe(false);
        });

        it("calling clearSuggestions while debounce timer is pending cancels the debounce and prevents delayed fetch", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(500);
            });
            expect(fetchMock).not.toHaveBeenCalled();

            act(() => {
                result.current.clearSuggestions();
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(DEBOUNCE_MS * 2);
            });

            expect(fetchMock).not.toHaveBeenCalled();
            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("");
            expect(result.current.loading).toBe(false);
        });
    });
});
