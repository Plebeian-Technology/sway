import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";

import { Combobox, type ComboboxOption } from "@/components/ui/combobox";

// @lat: [[combobox-primitive-design#WAI-ARIA combobox pattern and keyboard parity]]

describe("Combobox keyboard navigation", () => {
    beforeEach(() => {
        Element.prototype.scrollIntoView = vi.fn<(options?: ScrollIntoViewOptions) => void>();
    });

    afterEach(() => {
        cleanup();
    });

    it("advances active option only once per ArrowDown key press on a rendered option (no duplicate bubbling)", () => {
        const options: ComboboxOption[] = [
            { value: "opt-1", label: "Option 1" },
            { value: "opt-2", label: "Option 2" },
            { value: "opt-3", label: "Option 3" },
        ];
        render(<Combobox value={null} onValueChange={vi.fn<(value: string) => void>()} options={options} />);

        fireEvent.click(screen.getByRole("combobox"));
        const renderedOptions = screen.getAllByRole("option");
        expect(renderedOptions[0]).toHaveAttribute("data-active", "true");

        fireEvent.keyDown(renderedOptions[0], { key: "ArrowDown" });

        expect(renderedOptions[1]).toHaveAttribute("data-active", "true");
        expect(renderedOptions[0]).not.toHaveAttribute("data-active");
        expect(renderedOptions[2]).not.toHaveAttribute("data-active");
    });

    it("invokes onValueChange only once per Enter key press on a rendered option (no duplicate bubbling)", () => {
        const onValueChange = vi.fn<(value: string) => void>();
        const options: ComboboxOption[] = [
            { value: "opt-1", label: "Option 1" },
            { value: "opt-2", label: "Option 2" },
        ];
        render(<Combobox value={null} onValueChange={onValueChange} options={options} />);

        fireEvent.click(screen.getByRole("combobox"));
        const renderedOptions = screen.getAllByRole("option");

        fireEvent.keyDown(renderedOptions[0], { key: "Enter" });

        expect(onValueChange).toHaveBeenCalledTimes(1);
        expect(onValueChange).toHaveBeenCalledWith("opt-1");
    });

    it("sets data-active on the last enabled option when pressing End in search input with trailing disabled option", () => {
        const options: ComboboxOption[] = [
            { value: "opt-1", label: "Option 1" },
            { value: "opt-2", label: "Option 2" },
            { value: "opt-disabled", label: "Retired Option", disabled: true },
        ];
        render(<Combobox value={null} onValueChange={vi.fn<(value: string) => void>()} options={options} />);

        fireEvent.click(screen.getByRole("combobox"));
        const searchInput = screen.getByRole("textbox");

        fireEvent.keyDown(searchInput, { key: "End" });

        const renderedOptions = screen.getAllByRole("option");
        expect(renderedOptions[1]).toHaveAttribute("data-active", "true");
        expect(renderedOptions[2]).not.toHaveAttribute("data-active");
        expect(renderedOptions[2]).toHaveAttribute("aria-disabled", "true");
    });

    it("sets data-active on the first enabled option when pressing Home in search input with leading disabled option", () => {
        const options: ComboboxOption[] = [
            { value: "lead-disabled", label: "Deprecated Option", disabled: true },
            { value: "opt-1", label: "Option 1" },
            { value: "opt-2", label: "Option 2" },
        ];
        render(<Combobox value="opt-2" onValueChange={vi.fn<(value: string) => void>()} options={options} />);

        fireEvent.click(screen.getByRole("combobox"));
        const searchInput = screen.getByRole("textbox");

        fireEvent.keyDown(searchInput, { key: "Home" });

        const renderedOptions = screen.getAllByRole("option");
        expect(renderedOptions[1]).toHaveAttribute("data-active", "true");
        expect(renderedOptions[0]).not.toHaveAttribute("data-active");
        expect(renderedOptions[0]).toHaveAttribute("aria-disabled", "true");
    });

    it("initializes active option to the first enabled option when opening combobox with a disabled selected value", () => {
        const onValueChange = vi.fn<(value: string) => void>();
        const options: ComboboxOption[] = [
            { value: "retired", label: "Retired Option", disabled: true },
            { value: "enabled-1", label: "Enabled Option 1" },
            { value: "enabled-2", label: "Enabled Option 2" },
        ];
        render(<Combobox value="retired" onValueChange={onValueChange} options={options} />);

        fireEvent.click(screen.getByRole("combobox"));

        const renderedOptions = screen.getAllByRole("option");
        expect(renderedOptions[1]).toHaveAttribute("data-active", "true");
        expect(renderedOptions[0]).not.toHaveAttribute("data-active");

        const searchInput = screen.getByRole("textbox");
        fireEvent.keyDown(searchInput, { key: "Enter" });

        expect(onValueChange).toHaveBeenCalledTimes(1);
        expect(onValueChange).toHaveBeenCalledWith("enabled-1");
    });

    it("leaves no option active when opening combobox with all disabled options", () => {
        const onValueChange = vi.fn<(value: string) => void>();
        const options: ComboboxOption[] = [
            { value: "dis-1", label: "Retired 1", disabled: true },
            { value: "dis-2", label: "Retired 2", disabled: true },
        ];
        render(<Combobox value="dis-1" onValueChange={onValueChange} options={options} />);

        fireEvent.click(screen.getByRole("combobox"));

        const renderedOptions = screen.getAllByRole("option");
        for (const opt of renderedOptions) {
            expect(opt).not.toHaveAttribute("data-active");
        }

        const searchInput = screen.getByRole("textbox");
        expect(searchInput).not.toHaveAttribute("aria-activedescendant");

        fireEvent.keyDown(searchInput, { key: "Enter" });
        expect(onValueChange).not.toHaveBeenCalled();
    });

    it("sets active option to the first enabled option among visible results when typing a query", () => {
        const options: ComboboxOption[] = [
            { value: "gpt-3.5", label: "OpenAI: GPT-3.5 Legacy", disabled: true },
            { value: "gpt-4o", label: "OpenAI: GPT-4o" },
            { value: "claude-sonnet", label: "Anthropic: Claude Sonnet" },
        ];
        render(<Combobox value={null} onValueChange={vi.fn<(value: string) => void>()} options={options} />);

        fireEvent.click(screen.getByRole("combobox"));
        const searchInput = screen.getByRole("textbox");

        fireEvent.change(searchInput, { target: { value: "openai" } });

        const visibleOptions = screen.getAllByRole("option");
        expect(visibleOptions).toHaveLength(2);
        expect(visibleOptions[0]).toHaveTextContent("OpenAI: GPT-3.5 Legacy");
        expect(visibleOptions[1]).toHaveTextContent("OpenAI: GPT-4o");

        expect(visibleOptions[1]).toHaveAttribute("data-active", "true");
        expect(visibleOptions[0]).not.toHaveAttribute("data-active");
    });

    it("leaves no option active when typing a search query that filters to only disabled options", () => {
        const onValueChange = vi.fn<(value: string) => void>();
        const options: ComboboxOption[] = [
            { value: "retired-legacy", label: "Legacy Model", disabled: true },
            { value: "modern-model", label: "Modern Model" },
        ];
        render(<Combobox value={null} onValueChange={onValueChange} options={options} />);

        fireEvent.click(screen.getByRole("combobox"));
        const searchInput = screen.getByRole("textbox");

        fireEvent.change(searchInput, { target: { value: "legacy" } });

        const visibleOptions = screen.getAllByRole("option");
        expect(visibleOptions).toHaveLength(1);
        expect(visibleOptions[0]).not.toHaveAttribute("data-active");

        fireEvent.keyDown(searchInput, { key: "Enter" });
        expect(onValueChange).not.toHaveBeenCalled();
    });

    it("opens the popover when pressing ArrowDown on the closed combobox trigger", () => {
        const options: ComboboxOption[] = [
            { value: "opt-1", label: "Option 1" },
            { value: "opt-2", label: "Option 2" },
        ];
        render(<Combobox value="opt-2" onValueChange={vi.fn<(value: string) => void>()} options={options} />);

        const trigger = screen.getByRole("combobox");
        expect(trigger).toHaveAttribute("aria-expanded", "false");

        fireEvent.keyDown(trigger, { key: "ArrowDown" });

        expect(trigger).toHaveAttribute("aria-expanded", "true");
        const renderedOptions = screen.getAllByRole("option");
        expect(renderedOptions[1]).toHaveAttribute("data-active", "true");
    });

    it("falls back active option to first enabled option if active option becomes disabled while open", () => {
        const initialOptions: ComboboxOption[] = [
            { value: "opt-1", label: "Option 1" },
            { value: "opt-2", label: "Option 2" },
        ];
        const { rerender } = render(
            <Combobox value="opt-1" onValueChange={vi.fn<(value: string) => void>()} options={initialOptions} />,
        );

        fireEvent.click(screen.getByRole("combobox"));
        expect(screen.getAllByRole("option")[0]).toHaveAttribute("data-active", "true");

        const updatedOptions: ComboboxOption[] = [
            { value: "opt-1", label: "Option 1", disabled: true },
            { value: "opt-2", label: "Option 2" },
        ];
        rerender(<Combobox value="opt-1" onValueChange={vi.fn<(value: string) => void>()} options={updatedOptions} />);

        const renderedOptions = screen.getAllByRole("option");
        expect(renderedOptions[0]).not.toHaveAttribute("data-active");
        expect(renderedOptions[1]).toHaveAttribute("data-active", "true");
    });
});
