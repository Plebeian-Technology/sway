// Rails errors.to_hash sends a field's errors as a list, joined here into one line. The old code
// compared each MESSAGE to the field's NAME, so list-shaped errors never matched.

import { renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { sway } from "sway";

const useSwayFormContextMock = vi.fn<() => unknown>();
vi.mock("app/frontend/components/admin/creator/context/useSwayFormContext", () => ({
    useSwayFormContext: () => useSwayFormContextMock(),
}));

import { useErrorMessage } from "app/frontend/components/admin/creator/hooks/useErrorMessage";

const field = (name: string): sway.IFormField<Record<string, unknown>> =>
    ({
        name,
        component: "text",
        type: "text",
        label: name,
        isRequired: false,
    }) as unknown as sway.IFormField<Record<string, unknown>>;

describe("useErrorMessage", () => {
    it("joins array-shaped Rails errors into one string", () => {
        useSwayFormContextMock.mockReturnValue({ errors: { title: ["can't be blank", "is too short"] } });
        const { result } = renderHook(() => useErrorMessage(field("title")));
        expect(result.current).toBe("can't be blank, is too short");
    });

    it("returns a string-shaped error unchanged", () => {
        useSwayFormContextMock.mockReturnValue({ errors: { title: "is bad" } });
        const { result } = renderHook(() => useErrorMessage(field("title")));
        expect(result.current).toBe("is bad");
    });

    it("returns empty string when there is no error for the field", () => {
        useSwayFormContextMock.mockReturnValue({ errors: {} });
        const { result } = renderHook(() => useErrorMessage(field("title")));
        expect(result.current).toBe("");
    });
});
