import { beforeEach, describe, expect, it, vi } from "vitest";
import {
    createInertiaStubs,
    renderV2,
    resetInertiaStubs,
    setPageProps,
    type InertiaStubs,
} from "app/frontend/__tests__/test-utils";

const inertia: InertiaStubs = vi.hoisted(() => ({
    usePage: vi.fn<() => Record<string, unknown>>(() => ({ props: {} as Record<string, unknown> })),
    router: {
        visit: vi.fn<(url: string) => void>(),
        post: vi.fn<(url: string, data?: unknown) => void>(),
        put: vi.fn<(url: string, data?: unknown) => void>(),
        patch: vi.fn<(url: string, data?: unknown) => void>(),
        delete: vi.fn<(url: string) => void>(),
        get: vi.fn<(url: string) => void>(),
        reload: vi.fn<(opts?: Record<string, unknown>) => void>(),
        on: vi.fn<(type: string, callback: (event: Event) => void) => () => void>((type, callback) => {
            const eventName = `inertia:${type}`;
            document.addEventListener(eventName, callback as EventListener);
            return () => document.removeEventListener(eventName, callback as EventListener);
        }),
    },
}));

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        usePage: inertia.usePage,
        router: inertia.router,
    };
});

// Imported AFTER vi.mock, so the fake is in place before @inertiajs/react loads.
import { usePage, router } from "@inertiajs/react";

beforeEach(() => {
    resetInertiaStubs(inertia);
});

describe("renderV2", () => {
    it("wraps children in a data-theme='v2' root so v2 tokens.css selectors resolve", () => {
        const { getByTestId } = renderV2(<span data-testid="child">inside</span>);

        const child = getByTestId("child");
        expect(child.parentElement).toHaveAttribute("data-theme", "v2");
    });
});

describe("setPageProps", () => {
    it("returns props set via setPageProps from usePage()", () => {
        setPageProps(inertia, { bill: { id: 42, external_id: "HB0001" } });

        const { props } = usePage();

        expect(props).toEqual({ bill: { id: 42, external_id: "HB0001" } });
    });
});

describe("resetInertiaStubs", () => {
    it("clears usePage overrides back to empty props", () => {
        setPageProps(inertia, { foo: "bar" });
        resetInertiaStubs(inertia);

        const { props } = usePage();

        expect(props).toEqual({});
    });

    it("clears recorded router calls", () => {
        router.visit("/bills/1/edit");
        resetInertiaStubs(inertia);

        expect(inertia.router.visit).not.toHaveBeenCalled();
    });
});

describe("router spies", () => {
    it("records router.visit calls routed through the stubbed router", () => {
        router.visit("/admin/bill_creator/new");

        expect(inertia.router.visit).toHaveBeenCalledWith("/admin/bill_creator/new");
    });

    it("records router.post payloads", () => {
        router.post("/bills/run_pipeline", { stages: ["fetch-bills"], bill_id: null });

        expect(inertia.router.post).toHaveBeenCalledWith("/bills/run_pipeline", {
            stages: ["fetch-bills"],
            bill_id: null,
        });
    });
});

describe("createInertiaStubs (runtime, non-hoisted)", () => {
    it("produces a fresh InertiaStubs shape for fixtures that don't need vi.mock wiring", () => {
        const fresh = createInertiaStubs();

        expect(fresh.usePage).toBeTypeOf("function");
        expect(fresh.router.visit).toBeTypeOf("function");
        expect(fresh.usePage()).toEqual({ props: {} });
    });
});
