import { describe, it, expect, vi } from "vitest";

const worker = vi.hoisted(() => {
    const listeners = new Map<string, (event: any) => void>();
    const scope = {
        location: { origin: "https://sway.test" },
        __WB_MANIFEST: [],
        skipWaiting: vi.fn<() => Promise<void>>().mockResolvedValue(undefined),
        clients: { claim: vi.fn<() => Promise<void>>().mockResolvedValue(undefined) },
        addEventListener: (type: string, listener: (event: any) => void) => listeners.set(type, listener),
    };
    Object.defineProperty(globalThis, "self", { value: scope, configurable: true, writable: true });
    return { listeners, scope };
});

vi.mock("workbox-precaching", () => ({
    precacheAndRoute: vi.fn<(...args: unknown[]) => unknown>(),
    cleanupOutdatedCaches: vi.fn<(...args: unknown[]) => unknown>(),
}));
vi.mock("workbox-routing", () => ({ registerRoute: vi.fn<(...args: unknown[]) => unknown>() }));
vi.mock("workbox-strategies", () => ({ CacheFirst: vi.fn<(...args: unknown[]) => unknown>() }));
vi.mock("workbox-expiration", () => ({ ExpirationPlugin: vi.fn<(...args: unknown[]) => unknown>() }));
vi.mock("workbox-cacheable-response", () => ({ CacheableResponsePlugin: vi.fn<(...args: unknown[]) => unknown>() }));

import { registerRoute } from "workbox-routing";
import { CacheFirst } from "workbox-strategies";
import { precacheAndRoute } from "workbox-precaching";
import { CacheControlPlugin, isAdminAsset } from "app/frontend/service-worker/sw";

// @lat: [[client-caches-and-identity#Static worker lifecycle]]
describe("static-only worker", () => {
    it("registers only static asset routes and retains the build precache", () => {
        expect(precacheAndRoute).toHaveBeenCalledWith(worker.scope.__WB_MANIFEST);
        expect(registerRoute).toHaveBeenCalledTimes(1);
        expect(CacheFirst).toHaveBeenCalledWith(expect.objectContaining({ cacheName: "admin-assets" }));
    });

    it.each([
        "/bills/123",
        "/bill_of_the_month",
        "/scores/1",
        "/user_votes",
        "/influence",
        "/legislators",
        "/admin/bills",
        "/api_keys",
    ])("does not intercept HTML or Inertia pages at %s", (path) => {
        const matcher = vi.mocked(registerRoute).mock.calls[0][0] as (context: any) => boolean;
        const url = new URL(path, "https://sway.test");
        expect(matcher({ url, request: { mode: "navigate", headers: new Headers() } })).toBe(false);
        expect(matcher({ url, request: new Request(url, { headers: { "X-Inertia": "true" } }) })).toBe(false);
    });

    it("does not cache a navigation or Inertia response even under an admin asset path", () => {
        const matcher = vi.mocked(registerRoute).mock.calls[0][0] as (context: any) => boolean;
        const url = new URL("https://sway.test/vite/assets/admin/Index-a1b2c3d4.js");
        expect(matcher({ url, request: { mode: "navigate", headers: new Headers() } })).toBe(false);
        expect(matcher({ url, request: new Request(url, { headers: { "X-Inertia": "true" } }) })).toBe(false);
        expect(matcher({ url, request: new Request(url) })).toBe(true);
    });

    it("skips the old worker's optional update prompt", async () => {
        const waitUntil = vi.fn<(promise: Promise<void>) => void>();
        worker.listeners.get("install")!({ waitUntil });
        await waitUntil.mock.calls[0][0];
        expect(worker.scope.skipWaiting).toHaveBeenCalled();
    });

    it("evicts legacy page caches before taking control and preserves static caches", async () => {
        const stored = new Set(["inertia-pages", "inertia-navigations", "admin-assets", "workbox-precache"]);
        const remove = vi.fn<(name: string) => Promise<boolean>>(async (name: string) => stored.delete(name));
        vi.stubGlobal("caches", { delete: remove });
        worker.scope.clients.claim.mockImplementationOnce(async () => {
            expect(stored).toEqual(new Set(["admin-assets", "workbox-precache"]));
        });
        const waitUntil = vi.fn<(promise: Promise<void>) => void>();
        worker.listeners.get("activate")!({ waitUntil });
        await waitUntil.mock.calls[0][0];
        expect(remove.mock.calls.map(([name]) => name).sort()).toEqual(["inertia-navigations", "inertia-pages"]);
        expect(worker.scope.clients.claim).toHaveBeenCalled();
        vi.unstubAllGlobals();
    });

    it("acknowledges the network-only policy for authentication preflight", () => {
        const postMessage = vi.fn<(...args: unknown[]) => unknown>();
        worker.listeners.get("message")!({ data: { type: "DYNAMIC_PAGES_NETWORK_ONLY" }, ports: [{ postMessage }] });
        expect(postMessage).toHaveBeenCalledWith({ success: true });
    });
});

// @lat: [[client-caches-and-identity#What the page cache is allowed to hold]]
describe("CacheControlPlugin", () => {
    it("is attached to the static runtime strategy", () => {
        expect(CacheFirst).toHaveBeenCalledWith(
            expect.objectContaining({ plugins: expect.arrayContaining([CacheControlPlugin]) }),
        );
    });
    it.each(["no-store", "private, no-cache", 'no-cache="Set-Cookie"'])("rejects %s", async (header) => {
        expect(
            await CacheControlPlugin.cacheWillUpdate({
                response: new Response("", { headers: { "Cache-Control": header } }),
            }),
        ).toBeNull();
    });
    it("allows an ordinary asset response", async () => {
        const response = new Response("asset");
        expect(await CacheControlPlugin.cacheWillUpdate({ response })).toBe(response);
    });
});

describe("isAdminAsset", () => {
    it("matches an admin chunk, which the precache deliberately skips", () => {
        expect(isAdminAsset(new URL("https://sway.test/vite/assets/admin/Categories-a1b2c3d4.js"))).toBe(true);
    });

    it("does not match an ordinary chunk, which the precache already holds", () => {
        expect(isAdminAsset(new URL("https://sway.test/vite/assets/Home-a1b2c3d4.js"))).toBe(false);
    });

    // The build directory is not fixed: every verify run builds into its own
    // vite-test/run-<id>, so the matcher keys off the assets/admin/ segment
    // rather than a whole path.
    it("matches under a build directory other than the production one", () => {
        expect(isAdminAsset(new URL("https://sway.test/vite-test/run-7/assets/admin/Index-a1b2c3d4.js"))).toBe(true);
    });

    it("does not match another origin serving the same path", () => {
        expect(isAdminAsset(new URL("https://elsewhere.test/vite/assets/admin/Index-a1b2c3d4.js"))).toBe(false);
    });
});
