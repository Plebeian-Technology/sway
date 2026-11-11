// @lat: [[bill-creator-temp-storage-hook#Why the hide-indicator timer restarts on every blur]]

import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("app/frontend/components/bill/creator/TempBillStorage", () => ({
    TempBillStorage: class {
        set = vi.fn<(...args: unknown[]) => void>();
    },
}));

import { useTempStorage } from "app/frontend/components/admin/creator/hooks/useTempStorage";

// @lat: [[bill-creator-temp-storage-hook#useTempStorage.test.ts notes]]
const blur = (name: string) => ({ target: { name } }) as unknown as React.FocusEvent<HTMLInputElement>;

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe("useTempStorage — saved-indicator timer", () => {
    it("clears the indicator 3s after a blur, even a blur long after mount", () => {
        const { result } = renderHook(() => useTempStorage("k", {}));
        // @lat: [[bill-creator-temp-storage-hook#useTempStorage.test.ts notes]]
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(5000));

        act(() => result.current.onBlur(blur("title")));
        expect(result.current.blurredFieldName).toBe("title");

        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(3000));
        expect(result.current.blurredFieldName).toBe("");
    });

    it("restarts the clear timer on a second blur", () => {
        const { result } = renderHook(() => useTempStorage("k", {}));

        act(() => result.current.onBlur(blur("title")));
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(1000));
        act(() => result.current.onBlur(blur("link"))); // restart
        expect(result.current.blurredFieldName).toBe("link");

        // 2.5s after the SECOND blur — still within its 3s window.
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(2500));
        expect(result.current.blurredFieldName).toBe("link");

        // past 3s from the second blur → cleared.
        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(600));
        expect(result.current.blurredFieldName).toBe("");
    });
});

// @lat: [[bill-creator-temp-storage-hook#Why onBlur is a narrower union than it used to be]]
describe("useTempStorage — storing a field by name", () => {
    it("writes the draft and names the field, then clears it on the same timer", () => {
        const { result } = renderHook(() => useTempStorage("k", {}));

        act(() => result.current.storeField("status"));
        expect(result.current.blurredFieldName).toBe("status");

        // oxlint-disable-next-line typescript/no-floating-promises -- React Testing Library's act() types declare Promise<void> even for sync callbacks
        act(() => vi.advanceTimersByTime(3000));
        expect(result.current.blurredFieldName).toBe("");
    });
});
