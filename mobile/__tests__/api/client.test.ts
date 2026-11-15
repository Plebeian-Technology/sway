/**
 // @lat: [[mobile-api-client-contract#Errors]]
 */
import * as SecureStore from "expo-secure-store";
import { apiClient } from "../../src/api/client";
import {
    ApiRequestError,
    UnauthorizedError,
    RateLimitedError,
    NetworkError,
    GENERIC_ERROR_MESSAGE,
} from "../../src/api/errors";
import { BEARER_TOKEN_KEY, SESSION_ENVELOPE_KEY, API_BASE_URL } from "../../src/constants/api";
import { authEvents } from "../../src/auth/authEvents";
import { localeOverride } from "../../src/state/localeOverride";

const originalFetch = global.fetch;

function mockFetchResponse(body: unknown, init: { status?: number; ok?: boolean } = {}) {
    const status = init.status ?? 200;
    const ok = init.ok ?? (status >= 200 && status < 300);
    const text = typeof body === "string" ? body : JSON.stringify(body);
    return {
        ok,
        status,
        text: async () => text,
    } as unknown as Response;
}

describe("apiClient", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        global.fetch = jest.fn() as unknown as typeof fetch;
    });

    afterAll(() => {
        global.fetch = originalFetch;
    });

    test("GET without token sends Accept header but no Authorization", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
        (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse({ ok: true }));

        await apiClient.get("/api/v1/bootstrap");

        const [url, init] = (global.fetch as jest.Mock).mock.calls[0];
        expect(url).toBe(`${API_BASE_URL}/api/v1/bootstrap`);
        expect(init.method).toBe("GET");
        expect(init.headers["Accept"]).toBe("application/json");
        expect(init.headers["Authorization"]).toBeUndefined();
    });

    test("GET with token sends Authorization: Bearer <token>", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockImplementation(async (k: string) => {
            if (k === BEARER_TOKEN_KEY) return "T";
            return null;
        });
        (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse({ id: 42 }));

        const out = await apiClient.get<{ id: number }>("/bills/42");

        const [, init] = (global.fetch as jest.Mock).mock.calls[0];
        expect(init.headers["Authorization"]).toBe("Bearer T");
        expect(out).toEqual({ id: 42 });
    });

    test("GET forwards caller headers alongside JSON and bearer headers", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue("T");
        (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse({ id: 42 }));

        await apiClient.get("/bills/42", {
            headers: { "X-Sway-Omit-Props": "legislators" },
        });

        const [, init] = (global.fetch as jest.Mock).mock.calls[0];
        expect(init.headers).toMatchObject({
            Accept: "application/json",
            Authorization: "Bearer T",
            "X-Sway-Omit-Props": "legislators",
        });
    });

    test("POST sends Content-Type: application/json and stringified body", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue("T");
        (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse({ created: true }));

        await apiClient.post("/user_votes", { bill_id: 1, support: true });

        const [, init] = (global.fetch as jest.Mock).mock.calls[0];
        expect(init.method).toBe("POST");
        expect(init.headers["Content-Type"]).toBe("application/json");
        expect(init.body).toBe(JSON.stringify({ bill_id: 1, support: true }));
    });

    test("Non-2xx parses D-29 envelope and throws ApiRequestError with code/message/details", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
        (global.fetch as jest.Mock).mockResolvedValueOnce(
            mockFetchResponse(
                {
                    error: {
                        code: "validation_failed",
                        message: "Phone is invalid",
                        details: { phone: ["is invalid"] },
                    },
                },
                { status: 422 },
            ),
        );

        await expect(apiClient.post("/x", {})).rejects.toMatchObject({
            code: "validation_failed",
            message: "Phone is invalid",
            details: { phone: ["is invalid"] },
            status: 422,
        });
    });

    test("401 clears BOTH tokenStore and sessionStore and throws UnauthorizedError", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue("T");
        (global.fetch as jest.Mock).mockResolvedValueOnce(
            mockFetchResponse({ error: { code: "unauthorized", message: "nope" } }, { status: 401 }),
        );

        await expect(apiClient.get("/protected")).rejects.toBeInstanceOf(UnauthorizedError);

        expect(SecureStore.deleteItemAsync).toHaveBeenCalledWith(BEARER_TOKEN_KEY);
        expect(SecureStore.deleteItemAsync).toHaveBeenCalledWith(SESSION_ENVELOPE_KEY);
    });

    test("401 announces unauthenticated with the session_expired reason", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue("T");
        (global.fetch as jest.Mock).mockResolvedValueOnce(
            mockFetchResponse({ error: { code: "unauthorized", message: "nope" } }, { status: 401 }),
        );
        const emitSpy = jest.spyOn(authEvents, "emit");

        await expect(apiClient.post("/sway_registration", {})).rejects.toBeInstanceOf(UnauthorizedError);

        expect(emitSpy).toHaveBeenCalledWith("unauthenticated", "session_expired");
        emitSpy.mockRestore();
    });

    test("401 does NOT clear tokenStore/sessionStore when request had no token or token was superseded", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValueOnce("OLD_TOKEN").mockResolvedValueOnce("NEW_TOKEN");
        (global.fetch as jest.Mock).mockResolvedValueOnce(
            mockFetchResponse({ error: { code: "unauthorized", message: "stale" } }, { status: 401 }),
        );

        await expect(apiClient.get("/protected")).rejects.toBeInstanceOf(UnauthorizedError);
        expect(SecureStore.deleteItemAsync).not.toHaveBeenCalled();
    });

    test("429 throws RateLimitedError", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
        (global.fetch as jest.Mock).mockResolvedValueOnce(
            mockFetchResponse({ error: { code: "rate_limited", message: "slow down" } }, { status: 429 }),
        );
        await expect(apiClient.get("/x")).rejects.toBeInstanceOf(RateLimitedError);
    });

    test("429 carries the Retry-After seconds, and none when the header is absent", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
        (global.fetch as jest.Mock).mockResolvedValueOnce({
            ...mockFetchResponse({ error: { code: "rate_limited", message: "slow down" } }, { status: 429 }),
            headers: { get: (name: string) => (name === "Retry-After" ? "42" : null) },
        });
        await expect(apiClient.get("/x")).rejects.toMatchObject({ retryAfterSeconds: 42 });

        (global.fetch as jest.Mock).mockResolvedValueOnce(
            mockFetchResponse({ error: { code: "rate_limited", message: "slow down" } }, { status: 429 }),
        );
        await expect(apiClient.get("/x")).rejects.toMatchObject({ retryAfterSeconds: undefined });
    });

    test("Network failure throws NetworkError", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
        (global.fetch as jest.Mock).mockRejectedValueOnce(new Error("getaddrinfo ENOTFOUND"));
        await expect(apiClient.get("/x")).rejects.toBeInstanceOf(NetworkError);
    });

    test("204 returns undefined", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue("T");
        (global.fetch as jest.Mock).mockResolvedValueOnce({
            ok: true,
            status: 204,
            text: async () => "",
        } as unknown as Response);

        const out = await apiClient.delete("/api/v1/devices/1");
        expect(out).toBeUndefined();
    });

    describe("locale-override injection", () => {
        afterEach(() => {
            localeOverride.clear();
        });

        test("when localeOverride is set, sway_locale_id is appended to the URL", async () => {
            (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
            (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse({ ok: true }));
            localeOverride.set(42);

            await apiClient.get("/api/v1/bootstrap");

            const [url] = (global.fetch as jest.Mock).mock.calls[0];
            expect(url).toBe(`${API_BASE_URL}/api/v1/bootstrap?sway_locale_id=42`);
        });

        test("merges with an existing query string", async () => {
            (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
            (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse([]));
            localeOverride.set(7);

            await apiClient.get("/api/v1/bills?page=2");

            const [url] = (global.fetch as jest.Mock).mock.calls[0];
            expect(url).toBe(`${API_BASE_URL}/api/v1/bills?page=2&sway_locale_id=7`);
        });

        test("does not override an explicit sway_locale_id already in the URL", async () => {
            (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
            (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse({}));
            localeOverride.set(42);

            await apiClient.get("/api/v1/bootstrap?sway_locale_id=99");

            const [url] = (global.fetch as jest.Mock).mock.calls[0];
            expect(url).toBe(`${API_BASE_URL}/api/v1/bootstrap?sway_locale_id=99`);
        });

        test("when localeOverride is null, URL is unchanged", async () => {
            (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
            (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse({}));
            localeOverride.clear();

            await apiClient.get("/api/v1/bootstrap");

            const [url] = (global.fetch as jest.Mock).mock.calls[0];
            expect(url).toBe(`${API_BASE_URL}/api/v1/bootstrap`);
        });
    });

    test("ApiRequestError exported and thrown for generic 5xx", async () => {
        (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
        (global.fetch as jest.Mock).mockResolvedValueOnce(
            mockFetchResponse({ error: { code: "internal", message: "boom" } }, { status: 500 }),
        );
        await expect(apiClient.get("/x")).rejects.toBeInstanceOf(ApiRequestError);
    });
    describe("fallback message when the body has no usable text", () => {
        beforeEach(() => {
            (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
        });

        const rejection = async () => {
            try {
                await apiClient.get("/x");
            } catch (e) {
                return e as ApiRequestError;
            }
            throw new Error("expected apiClient.get to reject");
        };

        test("an HTML error page gives the friendly message and keeps the http_<status> code", async () => {
            (global.fetch as jest.Mock).mockResolvedValueOnce(
                mockFetchResponse("<html><body>Internal Server Error</body></html>", { status: 500 }),
            );
            const e = await rejection();
            expect(e).toBeInstanceOf(ApiRequestError);
            expect(e.code).toBe("http_500");
            expect(e.status).toBe(500);
            expect(e.message).toBe(GENERIC_ERROR_MESSAGE);
            expect(e.message).not.toMatch(/^HTTP/);
        });

        test("an empty body gives the same message", async () => {
            (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse("", { status: 502 }));
            const e = await rejection();
            expect(e.code).toBe("http_502");
            expect(e.message).toBe(GENERIC_ERROR_MESSAGE);
        });

        test("a JSON errors entry with no title and no detail keeps its code and gets the message", async () => {
            (global.fetch as jest.Mock).mockResolvedValueOnce(
                mockFetchResponse({ errors: [{ code: "boom" }] }, { status: 500 }),
            );
            const e = await rejection();
            expect(e.code).toBe("boom");
            expect(e.message).toBe(GENERIC_ERROR_MESSAGE);
        });

        test("a JSON errors entry with nothing in it gets the http_<status> code and the message", async () => {
            (global.fetch as jest.Mock).mockResolvedValueOnce(mockFetchResponse({ errors: [{}] }, { status: 500 }));
            const e = await rejection();
            expect(e.code).toBe("http_500");
            expect(e.message).toBe(GENERIC_ERROR_MESSAGE);
        });

        test("an error object with a code and no message keeps the code and gets the message", async () => {
            (global.fetch as jest.Mock).mockResolvedValueOnce(
                mockFetchResponse({ error: { code: "internal" } }, { status: 500 }),
            );
            const e = await rejection();
            expect(e.code).toBe("internal");
            expect(e.message).toBe(GENERIC_ERROR_MESSAGE);
        });

        test("a title or message in the body still wins over the fallback", async () => {
            (global.fetch as jest.Mock)
                .mockResolvedValueOnce(mockFetchResponse({ errors: [{ title: "Bill not found" }] }, { status: 404 }))
                .mockResolvedValueOnce(mockFetchResponse({ error: { code: "x", message: "Nope" } }, { status: 422 }));
            expect((await rejection()).message).toBe("Bill not found");
            expect((await rejection()).message).toBe("Nope");
        });
    });

    describe("timeout and caller abort", () => {
        const fetchThatRejectsOnAbort = () =>
            (global.fetch as jest.Mock).mockImplementation(
                (_url: string, init: RequestInit) =>
                    new Promise((_resolve, reject) => {
                        init.signal?.addEventListener("abort", () => reject(new Error("aborted")));
                    }),
            );

        beforeEach(() => {
            jest.useFakeTimers();
            (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(null);
            fetchThatRejectsOnAbort();
        });

        afterEach(() => {
            jest.useRealTimers();
        });

        test("a request that outlives the default 15 seconds ends in a NetworkError", async () => {
            const settled = apiClient.get("/x").catch((e: unknown) => e);
            await jest.advanceTimersByTimeAsync(14_999);
            await expect(Promise.race([settled, "pending"])).resolves.toBe("pending");
            await jest.advanceTimersByTimeAsync(1);
            await expect(settled).resolves.toBeInstanceOf(NetworkError);
        });

        test("a custom timeoutMs replaces the default", async () => {
            const settled = apiClient.get("/x", { timeoutMs: 2_000 }).catch((e: unknown) => e);
            await jest.advanceTimersByTimeAsync(2_000);
            await expect(settled).resolves.toBeInstanceOf(NetworkError);
        });

        test("aborting the caller signal while pending throws ApiRequestError with code aborted", async () => {
            const caller = new AbortController();
            const settled = apiClient.get("/x", { signal: caller.signal }).catch((e: unknown) => e);
            await jest.advanceTimersByTimeAsync(0);
            caller.abort();
            const e = (await settled) as ApiRequestError;
            expect(e).toBeInstanceOf(ApiRequestError);
            expect(e).not.toBeInstanceOf(NetworkError);
            expect(e.code).toBe("aborted");
        });
    });
});
