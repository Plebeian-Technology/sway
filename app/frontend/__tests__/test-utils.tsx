/* oxlint-disable react-refresh/only-export-components -- test-only render helpers; this file is never subject to React Fast Refresh. */
import type { ReactElement, ReactNode } from "react";
import { render, type RenderOptions, type RenderResult } from "@testing-library/react";
import { vi, type Mock } from "vitest";

/**
 * Test helpers for the V2 interface.
 *
 * `renderV2` wraps React Testing Library's render in a `data-theme="v2"`
 * element, so the rules in the v2 tokens.css file apply.
 *
 * `setPageProps` and `resetInertiaStubs` work on an `InertiaStubs` object
 * that each test must declare with `vi.hoisted`.
 // @lat: [[frontend-test-infrastructure-notes#test-utils.tsx: why vi.hoisted stubs can't call a helper function]]
 *
 * Usage pattern (copy verbatim):
 *
 *     import { beforeEach, describe, expect, it, vi } from "vitest";
 *     import { renderV2, setPageProps, resetInertiaStubs, type InertiaStubs } from "app/frontend/__tests__/test-utils";
 *
 *     const inertia: InertiaStubs = vi.hoisted(() => ({
 *         usePage: vi.fn(() => ({ props: {} as Record<string, unknown> })),
 *         router: {
 *             visit: vi.fn(), post: vi.fn(), put: vi.fn(),
 *             patch: vi.fn(), delete: vi.fn(), get: vi.fn(), reload: vi.fn(),
 *             // navigationStore calls router.on at module scope, and PageBodySlot
 *             // is in both layouts, so anything reaching a layout needs this.
 *             on: vi.fn((type: string, callback: (event: Event) => void) => {
 *                 const eventName = `inertia:${type}`;
 *                 document.addEventListener(eventName, callback as EventListener);
 *                 return () => document.removeEventListener(eventName, callback as EventListener);
 *             }),
 *         },
 *     }));
 *
 *     vi.mock("@inertiajs/react", async (importActual) => {
 *         const actual = await importActual<typeof import("@inertiajs/react")>();
 *         return { ...actual, usePage: inertia.usePage, router: inertia.router };
 *     });
 *
 *     beforeEach(() => {
 *         resetInertiaStubs(inertia);
 *         setPageProps(inertia, { bill: { id: 1 } });
 *     });
 */

export type RouterSpies = {
    visit: Mock;
    post: Mock;
    put: Mock;
    patch: Mock;
    delete: Mock;
    get: Mock;
    reload: Mock;
    on: Mock;
};

export type InertiaStubs = {
    usePage: Mock;
    router: RouterSpies;
};

export const createInertiaStubs = (): InertiaStubs => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>().mockReturnValue({ props: {} }),
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
});

export const setPageProps = (stubs: InertiaStubs, props: Record<string, unknown>): void => {
    stubs.usePage.mockReturnValue({ props });
};

export const resetInertiaStubs = (stubs: InertiaStubs): void => {
    stubs.usePage.mockReset();
    stubs.usePage.mockReturnValue({ props: {} });
    Object.values(stubs.router).forEach((spy) => spy.mockReset());
};

const V2Wrapper = ({ children }: { children: ReactNode }) => <div data-theme="v2">{children}</div>;

export const renderV2 = (ui: ReactElement, options?: RenderOptions): RenderResult =>
    render(ui, { wrapper: V2Wrapper, ...options });
