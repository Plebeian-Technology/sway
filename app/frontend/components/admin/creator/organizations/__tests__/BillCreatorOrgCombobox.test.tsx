import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { TOrganizationOption } from "app/frontend/components/admin/creator/types";

vi.mock("app/frontend/components/ui/input", () => ({
    Input: (props: React.InputHTMLAttributes<HTMLInputElement>) => <input {...props} />,
}));

vi.mock("app/frontend/components/admin/creator/organizations/BillCreatorOrgSelectedChips", () => ({
    default: ({ selected }: { selected: TOrganizationOption[] }) => (
        <div data-testid="selected-chips">{selected.length}</div>
    ),
}));

import BillCreatorOrgCombobox from "app/frontend/components/admin/creator/organizations/BillCreatorOrgCombobox";

const option = (value: number, label: string): TOrganizationOption => ({
    value,
    label,
    summary: "",
    support: "FOR",
});

afterEach(() => cleanup());

const setup = (overrides: Partial<React.ComponentProps<typeof BillCreatorOrgCombobox>> = {}) => {
    const onAppend = vi.fn<() => void>();
    const onRemove = vi.fn<() => void>();
    render(
        <BillCreatorOrgCombobox
            selected={[]}
            availableOptions={[option(1, "ACLU"), option(2, "Sierra Club"), option(3, "NAACP")]}
            onAppend={onAppend}
            onRemove={onRemove}
            {...overrides}
        />,
    );
    return { onAppend, onRemove, input: screen.getByPlaceholderText(/Search or create/) };
};

describe("BillCreatorOrgCombobox", () => {
    it("opens the dropdown on focus and lists unselected options", () => {
        const { input } = setup();
        fireEvent.focus(input);
        expect(screen.getByText("ACLU")).toBeInTheDocument();
        expect(screen.getByText("Sierra Club")).toBeInTheDocument();
    });

    it("excludes already-selected options from the list", () => {
        const { input } = setup({ selected: [option(1, "ACLU")] });
        fireEvent.focus(input);
        expect(screen.queryByText("ACLU")).not.toBeInTheDocument();
        expect(screen.getByText("NAACP")).toBeInTheDocument();
    });

    it("filters options by case-insensitive label substring", () => {
        const { input } = setup();
        fireEvent.change(input, { target: { value: "club" } });
        expect(screen.getByText("Sierra Club")).toBeInTheDocument();
        expect(screen.queryByText("ACLU")).not.toBeInTheDocument();
    });

    it("offers a Create action for a novel name", () => {
        const { input } = setup();
        fireEvent.change(input, { target: { value: "Brand New Org" } });
        expect(screen.getByText(/Create/)).toBeInTheDocument();
    });

    it("does not offer Create when the name matches an existing option", () => {
        const { input } = setup();
        fireEvent.change(input, { target: { value: "aclu" } });
        expect(screen.queryByText(/Create/)).not.toBeInTheDocument();
    });

    it("appends the chosen option on click", () => {
        const { onAppend, input } = setup();
        fireEvent.focus(input);
        fireEvent.click(screen.getByText("NAACP"));
        expect(onAppend).toHaveBeenCalledWith(expect.objectContaining({ value: 3, label: "NAACP" }));
    });

    it("Enter appends the first filtered option", () => {
        const { onAppend, input } = setup();
        fireEvent.change(input, { target: { value: "Sierra" } });
        fireEvent.keyDown(input, { key: "Enter" });
        expect(onAppend).toHaveBeenCalledWith(expect.objectContaining({ label: "Sierra Club" }));
    });

    it("Enter creates a new org with a monotonic negative id when nothing matches", () => {
        // The counter only decrements and never repeats, so the first inline create is
        // always -1. The old `-(selected.length + 1)` scheme reused ids and could revive
        // a cached removed row.
        const { onAppend, input } = setup({ selected: [option(1, "ACLU")] });
        fireEvent.change(input, { target: { value: "Fresh Coalition" } });
        fireEvent.keyDown(input, { key: "Enter" });
        expect(onAppend).toHaveBeenCalledWith(
            expect.objectContaining({ value: -1, label: "Fresh Coalition", support: "FOR" }),
        );
    });

    it("Escape closes the dropdown", () => {
        const { input } = setup();
        fireEvent.focus(input);
        expect(screen.getByText("ACLU")).toBeInTheDocument();
        fireEvent.keyDown(input, { key: "Escape" });
        expect(screen.queryByText("ACLU")).not.toBeInTheDocument();
    });

    it("closes the dropdown on an outside mousedown", () => {
        const { input } = setup();
        fireEvent.focus(input);
        expect(screen.getByText("ACLU")).toBeInTheDocument();
        fireEvent.mouseDown(document.body);
        expect(screen.queryByText("ACLU")).not.toBeInTheDocument();
    });

    it("lists all unselected options including newly created ones past the first 8", () => {
        const many = Array.from({ length: 12 }, (_, i) => option(i + 1, `Org ${i + 1}`));
        const { input } = setup({ availableOptions: many });
        fireEvent.focus(input);
        expect(screen.getAllByRole("button").filter((b) => b.textContent?.startsWith("Org"))).toHaveLength(12);
        expect(screen.getByText("Org 12")).toBeInTheDocument();
    });
});
