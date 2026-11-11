// @lat: [[district-chart-tooltip#The roster is fetched when a reader asks for it]]

import { fireEvent } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { renderV2, resetInertiaStubs, setPageProps, type InertiaStubs } from "app/frontend/__tests__/test-utils";

const inertia: InertiaStubs = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} as Record<string, unknown> })),
    router: {
        visit: vi.fn<(...args: unknown[]) => void>(),
        post: vi.fn<(...args: unknown[]) => void>(),
        put: vi.fn<(...args: unknown[]) => void>(),
        patch: vi.fn<(...args: unknown[]) => void>(),
        delete: vi.fn<(...args: unknown[]) => void>(),
        get: vi.fn<(...args: unknown[]) => void>(),
        reload: vi.fn<(...args: unknown[]) => void>(),
        on: vi.fn<(type: string, callback: (event: Event) => void) => () => void>((type, callback) => {
            const eventName = `inertia:${type}`;
            document.addEventListener(eventName, callback as EventListener);
            return () => document.removeEventListener(eventName, callback as EventListener);
        }),
    },
}));

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    return { ...actual, usePage: inertia.usePage, router: inertia.router };
});

import DistrictLabel from "app/frontend/components/bill/charts/DistrictLabel";

const district = { id: 7, name: "MD1", number: 1, region_code: "MD" };

describe("DistrictLabel", () => {
    beforeEach(() => {
        resetInertiaStubs(inertia);
    });

    it("asks for the legislators prop once, on the first hover", () => {
        const { getByText } = renderV2(<DistrictLabel district={district} label="MD1" />);

        fireEvent.pointerEnter(getByText("MD1"));
        fireEvent.pointerEnter(getByText("MD1"));
        fireEvent.focus(getByText("MD1"));

        expect(inertia.router.reload).toHaveBeenCalledTimes(1);
        expect(inertia.router.reload).toHaveBeenCalledWith({ only: ["legislators"] });
    });

    it("asks for nothing on a page that already carries the roster", () => {
        setPageProps(inertia, { legislators: [] });

        const { getByText } = renderV2(<DistrictLabel district={district} label="MD1" />);
        fireEvent.pointerEnter(getByText("MD1"));

        expect(inertia.router.reload).not.toHaveBeenCalled();
    });

    it("names the representative once the roster has arrived", () => {
        setPageProps(inertia, {
            legislators: [{ id: 3, full_name: "Ada Byron", district: { id: 7 } }],
        });

        const { getByText } = renderV2(<DistrictLabel district={district} label="MD1" />);

        expect(getByText("MD1")).toBeTruthy();
        expect(inertia.router.reload).not.toHaveBeenCalled();
    });
});
