import "@testing-library/jest-dom/vitest";
import { afterEach, beforeEach, vi } from "vitest";
import { cleanup } from "@testing-library/react";

// @lat: [[frontend-test-infrastructure-notes#setup.ts: the ResizeObserver stub]]
class ResizeObserverStub {
    observe() {}
    unobserve() {}
    disconnect() {}
}
if (typeof window !== "undefined" && !("ResizeObserver" in window)) {
    // @ts-expect-error – jsdom doesn't declare ResizeObserver
    window.ResizeObserver = ResizeObserverStub;
}

// @lat: [[frontend-test-infrastructure-notes#setup.ts: the matchMedia stub]]
const installMatchMediaStub = () => {
    window.matchMedia = vi.fn<(query: string) => MediaQueryList>().mockImplementation((query: string) => ({
        matches: false,
        media: query,
        onchange: null,
        addEventListener: vi.fn<(...args: unknown[]) => void>(),
        removeEventListener: vi.fn<(...args: unknown[]) => void>(),
        addListener: vi.fn<(...args: unknown[]) => void>(),
        removeListener: vi.fn<(...args: unknown[]) => void>(),
        dispatchEvent: vi.fn<(...args: unknown[]) => boolean>(),
    })) as unknown as typeof window.matchMedia;
};

beforeEach(() => {
    installMatchMediaStub();
});

afterEach(() => {
    cleanup();
});
