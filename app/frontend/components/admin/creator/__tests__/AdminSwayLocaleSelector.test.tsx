// @lat: [[bill-creator-shell#The Bill Creator shell#Why a Radix portal is stubbed rather than driven in tests]]

import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

const selectSpy = vi.fn<(props: Record<string, unknown>) => void>();

vi.mock("app/frontend/components/ui/select", () => ({
    Select: (props: Record<string, unknown>) => {
        selectSpy(props);
        return <div data-testid="mock-select">{props.children as React.ReactNode}</div>;
    },
    SelectTrigger: (props: Record<string, unknown>) => (
        <div data-testid={props["data-testid"] as string}>{props.children as React.ReactNode}</div>
    ),
    SelectValue: () => <span />,
    SelectContent: (props: Record<string, unknown>) => <div>{props.children as React.ReactNode}</div>,
    SelectItem: (props: Record<string, unknown>) => (
        <div data-testid={`locale-option-${props.value as string}`}>{props.children as React.ReactNode}</div>
    ),
}));

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useAdminSwayLocaleOptions: () => [
        { label: "Baltimore, Maryland", value: 1 },
        { label: "U.S. Congress", value: 2 },
        { label: "Maryland", value: 3 },
    ],
    useSwayLocale: () => [{ id: 1, name: "baltimore-maryland-united_states" }, vi.fn<() => void>()],
}));

import AdminSwayLocaleSelector from "app/frontend/components/admin/creator/AdminSwayLocaleSelector";

afterEach(() => {
    cleanup();
    selectSpy.mockClear();
});

describe("AdminSwayLocaleSelector", () => {
    it("renders every locale option from useAdminSwayLocaleOptions", () => {
        render(<AdminSwayLocaleSelector onSwayLocaleChange={vi.fn<(locale: number) => void>()} />);

        expect(screen.getByTestId("admin-locale-selector")).toBeInTheDocument();
        expect(screen.getByTestId("locale-option-1")).toHaveTextContent("Baltimore, Maryland");
        expect(screen.getByTestId("locale-option-2")).toHaveTextContent("U.S. Congress");
        expect(screen.getByTestId("locale-option-3")).toHaveTextContent("Maryland");
    });

    it("controls the Select with the current locale id", () => {
        render(<AdminSwayLocaleSelector onSwayLocaleChange={vi.fn<(locale: number) => void>()} />);

        expect(selectSpy).toHaveBeenCalledWith(expect.objectContaining({ value: "1" }));
    });

    // pendingSwayLocaleId wins over the confirmed server locale (same rule as useSwayLocales.ts
    // elsewhere), or the control would snap back to the old jurisdiction until navigation lands.
    it("shows the pending locale, not the confirmed one, while a switch is under way", () => {
        render(
            <AdminSwayLocaleSelector onSwayLocaleChange={vi.fn<(locale: number) => void>()} pendingSwayLocaleId={3} />,
        );

        expect(selectSpy).toHaveBeenCalledWith(expect.objectContaining({ value: "3" }));
    });

    it("forwards selection to onSwayLocaleChange as a number", () => {
        const onSwayLocaleChange = vi.fn<(locale: number) => void>();
        render(<AdminSwayLocaleSelector onSwayLocaleChange={onSwayLocaleChange} />);

        const { onValueChange } = selectSpy.mock.calls[0][0] as { onValueChange: (v: string) => void };
        onValueChange("2");

        expect(onSwayLocaleChange).toHaveBeenCalledExactlyOnceWith(2);
    });
});
