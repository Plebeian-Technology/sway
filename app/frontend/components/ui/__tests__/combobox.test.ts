import { describe, expect, it } from "vitest";
import { filterComboboxOptions, type ComboboxOption } from "@/components/ui/combobox-filter";

// @lat: [[bill-creator-shell#The Bill Creator shell#Why a Radix portal is stubbed rather than driven in tests]]

const options: ComboboxOption[] = [
    { value: "1", label: "HB0001 — Open Meetings Act", keywords: "HB0001" },
    { value: "2", label: "SB0055 — Transit Funding", keywords: "SB0055" },
    { value: "3", label: "CB0123 — Affordable Housing Ordinance", keywords: "CB0123" },
];

describe("filterComboboxOptions", () => {
    it("returns every option for an empty or whitespace-only query", () => {
        expect(filterComboboxOptions(options, "")).toHaveLength(3);
        expect(filterComboboxOptions(options, "   ")).toHaveLength(3);
    });

    it("matches case-insensitively on the label", () => {
        expect(filterComboboxOptions(options, "transit").map((o) => o.value)).toEqual(["2"]);
        expect(filterComboboxOptions(options, "HOUSING").map((o) => o.value)).toEqual(["3"]);
    });

    it("matches on a bill number (label contains the external id)", () => {
        expect(filterComboboxOptions(options, "sb0055").map((o) => o.value)).toEqual(["2"]);
    });

    it("matches on keywords that are not part of the visible label", () => {
        const hidden: ComboboxOption[] = [{ value: "9", label: "Council Bill 9", keywords: "zoning variance" }];
        expect(filterComboboxOptions(hidden, "zoning")).toHaveLength(1);
    });

    it("requires every whitespace-separated term to match (AND semantics)", () => {
        expect(filterComboboxOptions(options, "transit funding").map((o) => o.value)).toEqual(["2"]);
        expect(filterComboboxOptions(options, "transit housing")).toHaveLength(0);
    });

    it("returns an empty list when nothing matches", () => {
        expect(filterComboboxOptions(options, "zzz")).toHaveLength(0);
    });

    it("matches OpenRouter model slugs passed via keywords", () => {
        const modelOptions: ComboboxOption[] = [
            { value: "openai/gpt-4o", label: "OpenAI: GPT-4o", keywords: "openai/gpt-4o" },
            {
                value: "anthropic/claude-3.5-sonnet",
                label: "Anthropic: Claude 3.5 Sonnet",
                keywords: "anthropic/claude-3.5-sonnet",
            },
        ];
        expect(filterComboboxOptions(modelOptions, "openai/gpt-4o").map((o) => o.value)).toEqual(["openai/gpt-4o"]);
        expect(filterComboboxOptions(modelOptions, "gpt-4o").map((o) => o.value)).toEqual(["openai/gpt-4o"]);
        expect(filterComboboxOptions(modelOptions, "sonnet").map((o) => o.value)).toEqual([
            "anthropic/claude-3.5-sonnet",
        ]);
    });

    it("invalidates the WeakMap haystack cache when label or keywords mutate in place", () => {
        const mutableOption: ComboboxOption = {
            value: "mut-1",
            label: "Initial Label",
            keywords: "initial-keyword",
        };
        const list = [mutableOption];

        expect(filterComboboxOptions(list, "initial")).toHaveLength(1);
        expect(filterComboboxOptions(list, "updated")).toHaveLength(0);

        mutableOption.label = "Updated Label";
        expect(filterComboboxOptions(list, "updated")).toHaveLength(1);
        expect(filterComboboxOptions(list, "initial-keyword")).toHaveLength(1);

        mutableOption.keywords = "fresh-keyword";
        expect(filterComboboxOptions(list, "initial-keyword")).toHaveLength(0);
        expect(filterComboboxOptions(list, "fresh-keyword")).toHaveLength(1);
    });
});
