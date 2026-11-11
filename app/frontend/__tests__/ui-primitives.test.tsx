import { describe, expect, it } from "vitest";
import { Input } from "app/frontend/components/ui/input";
import { Textarea } from "app/frontend/components/ui/textarea";
import { SelectTrigger } from "app/frontend/components/ui/select";
import { Select as RadixSelect } from "radix-ui";
import { renderV2 } from "app/frontend/__tests__/test-utils";

describe("Input primitive", () => {
    it("applies the resting border-border-strong token and bg-input", () => {
        const { getByRole } = renderV2(<Input aria-label="title" defaultValue="" />);

        const input = getByRole("textbox");
        expect(input.className).toMatch(/border-border-strong/);
        expect(input.className).toMatch(/bg-input/);
    });

    it("wires the focus-visible 3px ring and border classes", () => {
        const { getByRole } = renderV2(<Input aria-label="title" />);

        const input = getByRole("textbox");
        expect(input.className).toMatch(/focus-visible:ring-\[3px\]/);
        expect(input.className).toMatch(/focus-visible:border-ring/);
    });

    it("wires the aria-invalid destructive ring classes", () => {
        const { getByRole } = renderV2(<Input aria-label="title" />);

        const input = getByRole("textbox");
        expect(input.className).toMatch(/aria-invalid:border-destructive/);
        expect(input.className).toMatch(/aria-invalid:ring-destructive/);
    });

    it("disables pointer events when disabled", () => {
        const { getByRole } = renderV2(<Input aria-label="title" disabled />);

        const input = getByRole("textbox");
        expect(input).toBeDisabled();
        expect(input.className).toMatch(/disabled:pointer-events-none/);
    });

    it("carries data-slot='input' for downstream theme selectors", () => {
        const { getByRole } = renderV2(<Input aria-label="title" />);

        expect(getByRole("textbox")).toHaveAttribute("data-slot", "input");
    });

    it("merges caller className with the base classes", () => {
        const { getByRole } = renderV2(<Input aria-label="title" className="custom-extra" />);

        const input = getByRole("textbox");
        expect(input.className).toMatch(/custom-extra/);
        expect(input.className).toMatch(/border-border-strong/);
    });
});

describe("Textarea primitive", () => {
    it("applies the resting border-border-strong token and bg-input", () => {
        const { getByRole } = renderV2(<Textarea aria-label="summary" />);

        const textarea = getByRole("textbox");
        expect(textarea.className).toMatch(/border-border-strong/);
        expect(textarea.className).toMatch(/bg-input/);
    });

    it("wires focus-visible ring classes", () => {
        const { getByRole } = renderV2(<Textarea aria-label="summary" />);

        const textarea = getByRole("textbox");
        expect(textarea.className).toMatch(/focus-visible:ring-\[3px\]/);
        expect(textarea.className).toMatch(/focus-visible:border-ring/);
    });

    it("carries data-slot='textarea'", () => {
        const { getByRole } = renderV2(<Textarea aria-label="summary" />);

        expect(getByRole("textbox")).toHaveAttribute("data-slot", "textarea");
    });
});

describe("SelectTrigger primitive", () => {
    const renderTrigger = (props?: React.ComponentProps<typeof SelectTrigger>) =>
        renderV2(
            <RadixSelect.Root>
                <SelectTrigger aria-label="chamber" {...props}>
                    <RadixSelect.Value placeholder="Select…" />
                </SelectTrigger>
            </RadixSelect.Root>,
        );

    it("applies the resting border-border-strong token and bg-input", () => {
        const { getByRole } = renderTrigger();

        const trigger = getByRole("combobox");
        expect(trigger.className).toMatch(/border-border-strong/);
        expect(trigger.className).toMatch(/bg-input/);
    });

    it("wires focus-visible ring classes", () => {
        const { getByRole } = renderTrigger();

        const trigger = getByRole("combobox");
        expect(trigger.className).toMatch(/focus-visible:ring-\[3px\]/);
        expect(trigger.className).toMatch(/focus-visible:border-ring/);
    });

    it("carries data-slot='select-trigger'", () => {
        const { getByRole } = renderTrigger();

        expect(getByRole("combobox")).toHaveAttribute("data-slot", "select-trigger");
    });

    it("honors data-size variants (default h-11, sm h-8)", () => {
        const { getByRole, rerender } = renderTrigger();

        expect(getByRole("combobox")).toHaveAttribute("data-size", "default");

        rerender(
            <div data-theme="v2">
                <RadixSelect.Root>
                    <SelectTrigger aria-label="chamber" size="sm">
                        <RadixSelect.Value placeholder="Select…" />
                    </SelectTrigger>
                </RadixSelect.Root>
            </div>,
        );

        expect(getByRole("combobox")).toHaveAttribute("data-size", "sm");
    });
});
