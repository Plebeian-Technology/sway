import { act, renderHook } from "@testing-library/react";
import type { InertiaFormProps } from "@inertiajs/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import {
    type AddressSuggestion,
    NOMINATIM_DEBOUNCE_MS,
    useNominatimAddressAutocomplete,
} from "app/frontend/hooks/useNominatimAddressAutocomplete";
import type { INominatimPlace } from "app/frontend/sway_utils/parseNominatimAddress";

interface ITestAddressForm extends Partial<sway.IAddress> {
    is_voter_registration_address_confirmed?: boolean;
    place_types?: string[];
    [key: string]: unknown;
}

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

const ANNAPOLIS_LOCALE: sway.ISwayLocale = {
    id: 2,
    name: "annapolis-maryland-united_states",
    city: "annapolis",
    region_code: "MD",
    region_name: "Maryland",
    country: "united_states",
    icon_url: "public/images/flags/annapolis-maryland-united_states.svg",
    time_zone: "America/New_York",
    current_session_start_date: "2025-01-01",
    default_bill_chamber: null,
    bill_chambers: null,
    nominatim_viewbox: "-76.5450,39.0200,-76.4650,38.9400",
    nominatim_bounded: true,
    nominatim_country_codes: "us",
};

const MARYLAND_LOCALE: sway.ISwayLocale = {
    id: 3,
    name: "maryland-maryland-united_states",
    city: "maryland",
    region_code: "MD",
    region_name: "Maryland",
    country: "united_states",
    icon_url: "public/images/flags/maryland-maryland-united_states.svg",
    time_zone: "America/New_York",
    current_session_start_date: "2025-01-08",
    default_bill_chamber: null,
    bill_chambers: null,
    nominatim_viewbox: "-79.4877,39.7230,-75.0489,37.9117",
    nominatim_bounded: true,
    nominatim_country_codes: "us",
};

const CONGRESS_LOCALE: sway.ISwayLocale = {
    id: 4,
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

describe("Adversarial Challenge: useNominatimAddressAutocomplete", () => {
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

    describe("Challenge Dimension 1: Debounce Timing & Rate Limiting", () => {
        it("collapses rapid keystrokes within 1000ms window into a single request", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            const keystrokes = ["1", "10", "100", "100 ", "100 H"];
            for (const text of keystrokes) {
                act(() => {
                    result.current.handleInput({
                        target: { value: text },
                    } as React.ChangeEvent<HTMLInputElement>);
                });
                await act(async () => {
                    await vi.advanceTimersByTimeAsync(100);
                });
            }

            expect(fetchMock).not.toHaveBeenCalled();

            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const calledUrl = getRequestedUrl(0);
            expect(calledUrl).toContain("q=100%20H");
        });

        it("resets 1000ms debounce timer when new keystroke arrives before expiry", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(800);
            });
            expect(fetchMock).not.toHaveBeenCalled();

            act(() => {
                result.current.handleInput({
                    target: { value: "100 H" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            await act(async () => {
                await vi.advanceTimersByTimeAsync(800);
            });
            expect(fetchMock).not.toHaveBeenCalled();

            await act(async () => {
                await vi.advanceTimersByTimeAsync(200);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const calledUrl = getRequestedUrl(0);
            expect(calledUrl).toContain("q=100%20H");
        });

        it("burst fuzzing with 20 keystrokes at 50ms intervals yields exactly 1 request", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            for (let i = 1; i <= 20; i++) {
                act(() => {
                    result.current.handleInput({
                        target: { value: `100 Holliday St ${i}` },
                    } as React.ChangeEvent<HTMLInputElement>);
                });
                await act(async () => {
                    await vi.advanceTimersByTimeAsync(50);
                });
            }

            expect(fetchMock).not.toHaveBeenCalled();

            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const calledUrl = getRequestedUrl(0);
            expect(calledUrl).toContain("q=100%20Holliday%20St%2020");
        });
    });

    describe("Challenge Dimension 2: Network Race Conditions & Concurrency", () => {
        it("out-of-order network responses: faster subsequent request takes precedence over slow initial request", async () => {
            let resolveSlow!: (res: Response) => void;
            const slowPromise = new Promise<Response>((resolve) => {
                resolveSlow = resolve;
            });

            let resolveFast!: (res: Response) => void;
            const fastPromise = new Promise<Response>((resolve) => {
                resolveFast = resolve;
            });

            fetchMock.mockReturnValueOnce(slowPromise).mockReturnValueOnce(fastPromise);

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Slow Query" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });
            expect(fetchMock).toHaveBeenCalledTimes(1);

            act(() => {
                result.current.handleInput({
                    target: { value: "Fast Query" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });
            expect(fetchMock).toHaveBeenCalledTimes(2);

            const fastPlace = createMockPlace({ place_id: 200, display_name: "Fast Street" });
            await act(async () => {
                resolveFast(createFetchResponse([fastPlace]));
            });

            expect(result.current.suggestions).toHaveLength(1);
            expect(result.current.suggestions[0]?.description).toBe("Fast Street");
            expect(result.current.status).toBe("OK");

            const slowPlace = createMockPlace({ place_id: 100, display_name: "Slow Street" });
            await act(async () => {
                resolveSlow(createFetchResponse([slowPlace]));
            });

            expect(result.current.suggestions).toHaveLength(1);
            expect(result.current.suggestions[0]?.description).toBe("Fast Street");
            expect(result.current.status).toBe("OK");
        });

        it("clearing input while request is in flight aborts/disregards response and resets loading", async () => {
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
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
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

        it("calling clearSuggestions while request is in flight cancels or disregards in-flight response", async () => {
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
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
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

        it("calling clearSuggestions while debounce timer is pending cancels the pending debounce", async () => {
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
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS * 2);
            });

            expect(fetchMock).not.toHaveBeenCalled();
            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("");
            expect(result.current.loading).toBe(false);
        });
    });

    describe("Challenge Dimension 3: Boundary & Lifecycle Safety", () => {
        it("selecting a suggestion immediately cancels pending debounce and in-flight fetch", async () => {
            const place = createMockPlace({ place_id: 555, display_name: "Selected Street" });
            fetchMock.mockResolvedValueOnce(createFetchResponse([place]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Selected" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.suggestions).toHaveLength(1);
            const suggestion = result.current.suggestions[0] as AddressSuggestion;

            act(() => {
                result.current.handleInput({
                    target: { value: "Selected More" },
                } as React.ChangeEvent<HTMLInputElement>);
            });

            act(() => {
                result.current.handleSelect(suggestion)();
            });

            expect(result.current.value).toBe("Selected Street");
            expect(form.setData).toHaveBeenCalledWith("street", "100 Holliday Street");

            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS * 2);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
        });

        it("unmounting hook while request is in flight aborts controller without unhandled errors", async () => {
            let capturedSignal: AbortSignal | undefined;
            const pendingPromise = new Promise<Response>(() => {});

            fetchMock.mockImplementationOnce((_url, init) => {
                capturedSignal = init?.signal as AbortSignal | undefined;
                return pendingPromise;
            });

            const form = buildMockForm();
            const { result, unmount } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            expect(capturedSignal).toBeDefined();
            expect(capturedSignal?.aborted).toBe(false);

            unmount();

            expect(capturedSignal?.aborted).toBe(true);
        });
    });

    describe("Challenge Dimension 4: Concurrency Fuzzing & Form Selection Integrity", () => {
        it("fuzzes rapid typing with interleaved backspaces across varied simulated latencies (10ms, 50ms, 500ms, 2000ms) without stranding loading: true", async () => {
            const deferredResolvers: Array<(res: Response) => void> = [];
            fetchMock.mockImplementation(() => {
                return new Promise<Response>((resolve) => {
                    deferredResolvers.push(resolve);
                });
            });

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            act(() => {
                result.current.handleInput({ target: { value: "10" } } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });
            expect(fetchMock).toHaveBeenCalledTimes(1);
            expect(result.current.loading).toBe(true);

            act(() => {
                result.current.handleInput({ target: { value: "1" } } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(50);
            });
            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });
            expect(fetchMock).toHaveBeenCalledTimes(2);

            const place2 = createMockPlace({ place_id: 2002, display_name: "100 Holliday Street Final" });
            const resolver2 = deferredResolvers[1];
            expect(resolver2).toBeDefined();
            await act(async () => {
                resolver2?.(createFetchResponse([place2]));
            });

            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toHaveLength(1);
            expect(result.current.suggestions[0]?.description).toBe("100 Holliday Street Final");

            const place1 = createMockPlace({ place_id: 1001, display_name: "10 Old Street Stale" });
            const resolver1 = deferredResolvers[0];
            expect(resolver1).toBeDefined();
            await act(async () => {
                resolver1?.(createFetchResponse([place1]));
            });

            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toHaveLength(1);
            expect(result.current.suggestions[0]?.description).toBe("100 Holliday Street Final");
            expect(result.current.status).toBe("OK");
        });

        it("rapid clear while slow 2000ms request is in flight followed by fast 10ms request displays only fast results", async () => {
            let resolveSlow!: (res: Response) => void;
            const slowPromise = new Promise<Response>((resolve) => {
                resolveSlow = resolve;
            });
            let resolveFast!: (res: Response) => void;
            const fastPromise = new Promise<Response>((resolve) => {
                resolveFast = resolve;
            });

            fetchMock.mockReturnValueOnce(slowPromise).mockReturnValueOnce(fastPromise);

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            act(() => {
                result.current.handleInput({
                    target: { value: "Slow Query 2000ms" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });
            expect(result.current.loading).toBe(true);

            act(() => {
                result.current.handleInput({ target: { value: "" } } as React.ChangeEvent<HTMLInputElement>);
            });
            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("IDLE");
            expect(result.current.loading).toBe(false);

            act(() => {
                result.current.handleInput({
                    target: { value: "Fast Query 10ms" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });
            expect(fetchMock).toHaveBeenCalledTimes(2);

            const fastPlace = createMockPlace({ place_id: 3003, display_name: "300 Fast Lane" });
            await act(async () => {
                resolveFast(createFetchResponse([fastPlace]));
            });

            expect(result.current.suggestions).toHaveLength(1);
            expect(result.current.suggestions[0]?.description).toBe("300 Fast Lane");
            expect(result.current.status).toBe("OK");
            expect(result.current.loading).toBe(false);

            const slowPlace = createMockPlace({ place_id: 9009, display_name: "900 Slow Place Stale" });
            await act(async () => {
                resolveSlow(createFetchResponse([slowPlace]));
            });

            expect(result.current.suggestions).toHaveLength(1);
            expect(result.current.suggestions[0]?.description).toBe("300 Fast Lane");
            expect(result.current.status).toBe("OK");
            expect(result.current.loading).toBe(false);
        });

        it("form selection integrity: handleSelect under concurrent in-flight network activity sets all form fields and discards late responses", async () => {
            const place1 = createMockPlace({
                place_id: 5001,
                lat: "39.29038",
                lon: "-76.61219",
                display_name: "100 Holliday Street, Baltimore, MD, 21202",
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
            fetchMock.mockResolvedValueOnce(createFetchResponse([place1]));

            let resolveSlowInFlight!: (res: Response) => void;
            const slowInFlightPromise = new Promise<Response>((resolve) => {
                resolveSlowInFlight = resolve;
            });

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.suggestions).toHaveLength(1);
            const selectedSuggestion = result.current.suggestions[0] as AddressSuggestion;

            fetchMock.mockReturnValueOnce(slowInFlightPromise);
            act(() => {
                result.current.handleInput({ target: { value: "200 Pratt" } } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });
            expect(fetchMock).toHaveBeenCalledTimes(2);
            expect(result.current.loading).toBe(true);

            act(() => {
                result.current.handleSelect(selectedSuggestion)();
            });

            expect(form.setData).toHaveBeenCalledWith("street", "100 Holliday Street");
            expect(form.setData).toHaveBeenCalledWith("city", "Baltimore");
            expect(form.setData).toHaveBeenCalledWith("region_code", "MD");
            expect(form.setData).toHaveBeenCalledWith("postal_code", "21202");
            expect(form.setData).toHaveBeenCalledWith("latitude", 39.29038);
            expect(form.setData).toHaveBeenCalledWith("longitude", -76.61219);
            expect(result.current.value).toBe("100 Holliday Street, Baltimore, MD, 21202");
            expect(result.current.suggestions).toEqual([]);
            expect(result.current.loading).toBe(false);

            const slowPlace = createMockPlace({ place_id: 8888, display_name: "200 Pratt Street Stale" });
            await act(async () => {
                resolveSlowInFlight(createFetchResponse([slowPlace]));
            });

            expect(result.current.suggestions).toEqual([]);
            expect(result.current.value).toBe("100 Holliday Street, Baltimore, MD, 21202");
            expect(result.current.loading).toBe(false);
        });

        it("chaotic burst fuzzing with interleaved typing, backspaces, clear, and clearSuggestions never strands loading", async () => {
            const deferredList: Array<(res: Response) => void> = [];
            fetchMock.mockImplementation(() => {
                return new Promise<Response>((resolve) => {
                    deferredList.push(resolve);
                });
            });

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            const inputs = [
                "a",
                "ab",
                "abc",
                "",
                "d",
                "de",
                "def",
                "de",
                "d",
                "",
                "100",
                "100 ",
                "100 H",
                "100 Ho",
                "100 Hol",
            ];

            for (const val of inputs) {
                act(() => {
                    result.current.handleInput({ target: { value: val } } as React.ChangeEvent<HTMLInputElement>);
                });
                await act(async () => {
                    await vi.advanceTimersByTimeAsync(150);
                });
            }

            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            act(() => {
                result.current.clearSuggestions();
            });

            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("");
            expect(result.current.loading).toBe(false);

            for (let i = 0; i < deferredList.length; i++) {
                const resolver = deferredList[i];
                await act(async () => {
                    resolver?.(createFetchResponse([createMockPlace({ place_id: 7000 + i })]));
                });
            }

            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
            expect(result.current.status).toBe("");
        });
    });

    describe("Challenge Dimension 5: SwayLocale Boundary Parameter Injection Across All Locales", () => {
        it("injects exact Baltimore City geographic boundaries: viewbox=-76.7114,39.3720,-76.5297,39.1972, bounded=1, countrycodes=us", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, BALTIMORE_LOCALE));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const url = new URL(getRequestedUrl(0));
            expect(url.searchParams.get("viewbox")).toBe("-76.7114,39.3720,-76.5297,39.1972");
            expect(url.searchParams.get("bounded")).toBe("1");
            expect(url.searchParams.get("countrycodes")).toBe("us");
            expect(url.searchParams.get("q")).toBe("100 Holliday");
        });

        it("injects exact Annapolis geographic boundaries: viewbox=-76.5450,39.0200,-76.4650,38.9400, bounded=1, countrycodes=us", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, ANNAPOLIS_LOCALE));

            act(() => {
                result.current.handleInput({
                    target: { value: "State Circle" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const url = new URL(getRequestedUrl(0));
            expect(url.searchParams.get("viewbox")).toBe("-76.5450,39.0200,-76.4650,38.9400");
            expect(url.searchParams.get("bounded")).toBe("1");
            expect(url.searchParams.get("countrycodes")).toBe("us");
            expect(url.searchParams.get("q")).toBe("State Circle");
        });

        it("injects exact Maryland statewide geographic boundaries: viewbox=-79.4877,39.7230,-75.0489,37.9117, bounded=1, countrycodes=us", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, MARYLAND_LOCALE));

            act(() => {
                result.current.handleInput({
                    target: { value: "Rockville Pike" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const url = new URL(getRequestedUrl(0));
            expect(url.searchParams.get("viewbox")).toBe("-79.4877,39.7230,-75.0489,37.9117");
            expect(url.searchParams.get("bounded")).toBe("1");
            expect(url.searchParams.get("countrycodes")).toBe("us");
            expect(url.searchParams.get("q")).toBe("Rockville Pike");
        });

        it("injects Congress unbounded configuration: null viewbox, bounded=0 (or omitted), countrycodes=us", async () => {
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, undefined, CONGRESS_LOCALE));

            act(() => {
                result.current.handleInput({
                    target: { value: "Independence Ave" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const url = new URL(getRequestedUrl(0));
            expect(url.searchParams.has("viewbox")).toBe(false);
            const bounded = url.searchParams.get("bounded");
            expect(bounded === null || bounded === "0").toBe(true);
            expect(url.searchParams.get("countrycodes")).toBe("us");
            expect(url.searchParams.get("q")).toBe("Independence Ave");
        });

        it("gracefully falls back to default search without viewbox or countrycodes when locale is null or undefined", async () => {
            const formNull = buildMockForm();
            const { result: resultNull } = renderHook(() => useNominatimAddressAutocomplete(formNull, undefined, null));

            act(() => {
                resultNull.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const urlNull = new URL(getRequestedUrl(0));
            expect(urlNull.searchParams.get("q")).toBe("100 Holliday");
            expect(urlNull.searchParams.has("viewbox")).toBe(false);
            expect(urlNull.searchParams.has("bounded")).toBe(false);

            fetchMock.mockClear();

            const formUndefined = buildMockForm();
            const { result: resultUndefined } = renderHook(() =>
                useNominatimAddressAutocomplete(formUndefined, undefined, undefined),
            );

            act(() => {
                resultUndefined.current.handleInput({
                    target: { value: "Main St" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const urlUndefined = new URL(getRequestedUrl(0));
            expect(urlUndefined.searchParams.get("q")).toBe("Main St");
            expect(urlUndefined.searchParams.has("viewbox")).toBe(false);
            expect(urlUndefined.searchParams.has("bounded")).toBe(false);
        });

        it("defends against empty or whitespace viewbox with bounded=true by suppressing both viewbox and bounded", async () => {
            const anomalyLocale: sway.ISwayLocale = {
                ...BALTIMORE_LOCALE,
                nominatim_viewbox: "",
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
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const url = new URL(getRequestedUrl(0));
            expect(url.searchParams.has("viewbox")).toBe(false);
            expect(url.searchParams.has("bounded")).toBe(false);
        });

        it("normalizes mixed-case country codes to lowercase (e.g. 'US' -> 'us')", async () => {
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
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(fetchMock).toHaveBeenCalledTimes(1);
            const url = new URL(getRequestedUrl(0));
            expect(url.searchParams.get("countrycodes")).toBe("us,ca");
        });

        it("dynamically adapts boundary parameters when locale changes between renders", async () => {
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
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
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
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            const url2 = new URL(getRequestedUrl(1));
            expect(url2.searchParams.has("viewbox")).toBe(false);
            expect(url2.searchParams.get("q")).toBe("Query 2");
        });
    });

    describe("Challenge Dimension 6: HTTP Error & Malformed Payload Stress Testing", () => {
        it("HTTP 429 Too Many Requests: sets status='ERROR', loading=false, suggestions=[] and invokes external setLoading(false)", async () => {
            fetchMock.mockResolvedValueOnce(
                createFetchResponse({ error: "Bandwidth limit exceeded" }, 429, "Too Many Requests"),
            );

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
            expect(setLoadingMock).toHaveBeenLastCalledWith(false);
        });

        it("HTTP 500 Internal Server Error: sets status='ERROR', loading=false, suggestions=[]", async () => {
            fetchMock.mockResolvedValueOnce(createFetchResponse(null, 500, "Internal Server Error"));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("HTTP 502/503/504 Upstream Failures: sets status='ERROR', loading=false, suggestions=[]", async () => {
            const errorStatuses = [502, 503, 504];
            for (const errStatus of errorStatuses) {
                fetchMock.mockResolvedValueOnce(createFetchResponse(null, errStatus, `Error ${errStatus}`));

                const form = buildMockForm();
                const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

                act(() => {
                    result.current.handleInput({
                        target: { value: `Query ${errStatus}` },
                    } as React.ChangeEvent<HTMLInputElement>);
                });
                await act(async () => {
                    await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
                });

                expect(result.current.status).toBe("ERROR");
                expect(result.current.loading).toBe(false);
                expect(result.current.suggestions).toEqual([]);
            }
        });

        it("Network exception (fetch throws TypeError 'Failed to fetch'): sets status='ERROR', loading=false, suggestions=[]", async () => {
            fetchMock.mockRejectedValueOnce(new TypeError("Failed to fetch"));

            const setLoadingMock = vi.fn<(loading: boolean) => void>();
            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form, setLoadingMock));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
            expect(setLoadingMock).toHaveBeenLastCalledWith(false);
        });

        it("Network exception (fetch throws DOMException 'NetworkError'): sets status='ERROR', loading=false, suggestions=[]", async () => {
            fetchMock.mockRejectedValueOnce(new DOMException("Network request failed", "NetworkError"));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "100 Holliday" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("Malformed JSON non-array object response: sets status='ERROR', loading=false, suggestions=[]", async () => {
            fetchMock.mockResolvedValueOnce(createFetchResponse({ error: "Invalid query syntax", code: 400 }));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Invalid Search" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("Malformed HTML error response (e.g. proxy HTML response): sets status='ERROR', loading=false, suggestions=[]", async () => {
            fetchMock.mockResolvedValueOnce({
                ok: true,
                status: 200,
                statusText: "OK",
                json: async () => {
                    throw new SyntaxError("Unexpected token '<', \"<html>...\" is not valid JSON");
                },
                headers: new Headers({ "Content-Type": "text/html" }),
            } as unknown as Response);

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "HTML Error" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("Empty array response: sets status='ZERO_RESULTS', loading=false, suggestions=[]", async () => {
            fetchMock.mockResolvedValueOnce(createFetchResponse([]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Nonexistent Address" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ZERO_RESULTS");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("Corrupt array containing null, undefined, boolean, numbers, string primitives: filters invalid entries and preserves valid ones", async () => {
            const malformedArray = [
                null,
                undefined,
                42,
                "string",
                true,
                createMockPlace({ place_id: "valid-1", display_name: "Valid Place 1" }),
            ];
            fetchMock.mockResolvedValueOnce(createFetchResponse(malformedArray));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Mixed Array" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("OK");
            expect(result.current.suggestions).toHaveLength(1);
            expect(result.current.suggestions[0]?.place_id).toBe("valid-1");
        });

        it("Corrupt place object with null/missing display_name, address, and coordinates: formats safely without throwing", async () => {
            const emptyPlace: INominatimPlace = {
                place_id: "corrupted-99",
                display_name: "",
            };
            fetchMock.mockResolvedValueOnce(createFetchResponse([emptyPlace]));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Empty Place" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("OK");
            expect(result.current.suggestions).toHaveLength(1);
            expect(result.current.suggestions[0]?.place_id).toBe("corrupted-99");
            expect(result.current.suggestions[0]?.description).toBe("");

            act(() => {
                result.current.handleSelect(result.current.suggestions[0] as AddressSuggestion)();
            });

            expect(result.current.value).toBe("");
            expect(result.current.suggestions).toEqual([]);
        });

        it("AbortError (DOMException) is silently suppressed without setting status to ERROR or breaking hook state", async () => {
            const abortError = new DOMException("The user aborted a request.", "AbortError");
            fetchMock.mockRejectedValueOnce(abortError);

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Aborted Request" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).not.toBe("ERROR");
            expect(result.current.status).toBe("IDLE");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("AbortError (Error with name='AbortError') is silently suppressed without setting status to ERROR", async () => {
            const abortError = new Error("The user aborted a request.");
            abortError.name = "AbortError";
            fetchMock.mockRejectedValueOnce(abortError);

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Aborted Standard Error" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).not.toBe("ERROR");
            expect(result.current.status).toBe("IDLE");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("cross-realm duck-typed AbortError object is silently suppressed without setting status to ERROR", async () => {
            fetchMock.mockRejectedValueOnce({
                name: "AbortError",
                message: "The operation was aborted.",
            });

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Cross Realm Abort" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).not.toBe("ERROR");
            expect(result.current.status).toBe("IDLE");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });

        it("non-abort DOMException (e.g. TimeoutError) transitions hook status to ERROR", async () => {
            fetchMock.mockRejectedValueOnce(new DOMException("The operation timed out.", "TimeoutError"));

            const form = buildMockForm();
            const { result } = renderHook(() => useNominatimAddressAutocomplete(form));

            act(() => {
                result.current.handleInput({
                    target: { value: "Timed Out Request" },
                } as React.ChangeEvent<HTMLInputElement>);
            });
            await act(async () => {
                await vi.advanceTimersByTimeAsync(NOMINATIM_DEBOUNCE_MS);
            });

            expect(result.current.status).toBe("ERROR");
            expect(result.current.loading).toBe(false);
            expect(result.current.suggestions).toEqual([]);
        });
    });
});
