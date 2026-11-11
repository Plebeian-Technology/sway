import type * as React from "react";

export interface ComboboxOption {
    /** Stable value passed to onValueChange when this option is chosen. */
    value: string;
    /** Text shown in the trigger + searched against. */
    label: string;
    /** Extra searchable text not rendered (e.g. a bill number, sponsor). */
    keywords?: string;
    /** Optional rich row content rendered instead of the plain label. */
    node?: React.ReactNode;
    disabled?: boolean;
}

const haystackCache = new WeakMap<ComboboxOption, { label: string; keywords: string | undefined; haystack: string }>();

const getOptionHaystack = (option: ComboboxOption): string => {
    const cached = haystackCache.get(option);
    if (cached && cached.label === option.label && cached.keywords === option.keywords) {
        return cached.haystack;
    }
    const haystack = `${option.label} ${option.keywords ?? ""}`.toLowerCase();
    haystackCache.set(option, { label: option.label, keywords: option.keywords, haystack });
    return haystack;
};

// @lat: [[combobox-primitive-design#Why filterComboboxOptions is a separate pure function]]
export const filterComboboxOptions = (options: ComboboxOption[], query: string): ComboboxOption[] => {
    const q = query.trim().toLowerCase();
    if (!q) return options;
    const terms = q.split(/\s+/);
    return options.filter((option) => {
        const haystack = getOptionHaystack(option);
        return terms.every((term) => haystack.includes(term));
    });
};
