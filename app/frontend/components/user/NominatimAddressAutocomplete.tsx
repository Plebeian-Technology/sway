// @lat: [[locale-extension#Nominatim geographic configuration]]
import type { InertiaFormProps } from "@inertiajs/react";
import { Loader2 } from "lucide-react";
import React, { useCallback, useEffect, useId, useRef, useState } from "react";
import type { sway } from "sway";

import { useNominatimAddressAutocomplete } from "app/frontend/hooks/useNominatimAddressAutocomplete";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { cn } from "app/frontend/lib/utils";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

export interface INominatimAddressAutocompleteProps<T = sway.IUser, TForm extends object = Record<string, unknown>> {
    form: InertiaFormProps<TForm>;
    field: sway.IFormField<T>;
    setLoading?: (loading: boolean) => void;
    locale?: sway.ISwayLocale | null;
    placeholder?: string;
}

// @lat: [[registration-dead-ends#An address search that finds nothing or fails still says the typed address can be submitted]]
const SEARCH_MESSAGES: Record<string, string | undefined> = {
    ZERO_RESULTS: PARITY_COPY.address.search.noResults,
    ERROR: PARITY_COPY.address.search.failed,
};

const NominatimAddressAutocomplete: React.FC<INominatimAddressAutocompleteProps> = ({
    form,
    field,
    setLoading,
    locale,
    placeholder = "1 W Elm St",
}) => {
    const { value, status, suggestions, loading, handleInput, handleSelect, clearSuggestions } =
        useNominatimAddressAutocomplete(form, setLoading, locale);

    const [activeIndex, setActiveIndex] = useState(-1);
    const containerRef = useRef<HTMLDivElement | null>(null);

    const listboxId = useId();
    const optionId = (index: number) => `${listboxId}-option-${index}`;
    const isOpen = status === "OK" && suggestions.length > 0;
    const searchMessage = loading ? null : SEARCH_MESSAGES[status];

    const formErrors = (form.errors ?? {}) as Record<string, string | undefined>;
    const { code: _errorCode, ...errorsWithoutCode } = formErrors;
    const errorMessage = formErrors[field.name as string] ?? formErrors.message ?? Object.values(errorsWithoutCode)[0];
    const errorId = `${field.name}-error`;

    const handleInputChange = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            setActiveIndex(-1);
            handleInput(e);
        },
        [handleInput],
    );

    const handleKeyDown = useCallback(
        (e: React.KeyboardEvent<HTMLInputElement>) => {
            if (!isOpen) return;
            switch (e.key) {
                case "ArrowDown":
                    e.preventDefault();
                    setActiveIndex((i) => (i + 1) % suggestions.length);
                    break;
                case "ArrowUp":
                    e.preventDefault();
                    setActiveIndex((i) => (i <= 0 ? suggestions.length - 1 : i - 1));
                    break;
                case "Enter": {
                    const selected = activeIndex >= 0 ? suggestions[activeIndex] : undefined;
                    if (selected) {
                        e.preventDefault();
                        handleSelect(selected)();
                        setActiveIndex(-1);
                    }
                    break;
                }
                case "Escape":
                    e.preventDefault();
                    clearSuggestions();
                    setActiveIndex(-1);
                    break;
            }
        },
        [activeIndex, clearSuggestions, handleSelect, isOpen, suggestions],
    );

    useEffect(() => {
        if (!isOpen) return;
        const handleOutsideClick = (e: MouseEvent | TouchEvent) => {
            if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
                clearSuggestions();
                setActiveIndex(-1);
            }
        };

        document.addEventListener("mousedown", handleOutsideClick);
        document.addEventListener("touchstart", handleOutsideClick);
        return () => {
            document.removeEventListener("mousedown", handleOutsideClick);
            document.removeEventListener("touchstart", handleOutsideClick);
        };
    }, [isOpen, clearSuggestions]);

    return (
        <div ref={containerRef} className="space-y-2">
            <Label htmlFor={field.name}>{field.label}</Label>
            <div className="relative">
                <Input
                    id={field.name}
                    name={field.name}
                    autoComplete="off"
                    value={value}
                    onChange={handleInputChange}
                    onKeyDown={handleKeyDown}
                    required={field.isRequired}
                    // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role lat:ignore
                    role="combobox"
                    aria-expanded={isOpen}
                    aria-controls={isOpen ? listboxId : undefined}
                    aria-autocomplete="list"
                    aria-activedescendant={activeIndex >= 0 ? optionId(activeIndex) : undefined}
                    aria-invalid={Boolean(errorMessage)}
                    aria-describedby={errorMessage ? errorId : undefined}
                    aria-busy={loading}
                    disabled={field.disabled}
                    placeholder={(field as { placeholder?: string }).placeholder ?? placeholder}
                    className={cn(loading && "pr-10")}
                />
                {loading && (
                    <div
                        data-testid="address-autocomplete-loading"
                        // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role lat:ignore
                        role="status"
                        aria-label="Loading address suggestions"
                        className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3"
                    >
                        <Loader2 className="size-4 animate-spin text-muted-foreground" />
                    </div>
                )}
            </div>

            {searchMessage && (
                <p
                    data-testid="address-search-message"
                    // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role lat:ignore
                    role="status"
                    className="text-sm text-muted-foreground"
                >
                    {searchMessage}
                </p>
            )}

            {isOpen && (
                <ul
                    id={listboxId}
                    // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role jsx-a11y/no-noninteractive-element-to-interactive-role lat:ignore
                    role="listbox"
                    aria-label={field.label || "Address suggestions"}
                    className="mt-1 divide-y divide-border rounded-xl border-neo border-border bg-card shadow-neo"
                >
                    {suggestions.map((suggestion, index) => {
                        const {
                            place_id,
                            structured_formatting: { main_text, secondary_text },
                        } = suggestion;
                        return (
                            // oxlint-disable-next-line jsx-a11y/click-events-have-key-events lat:ignore
                            <li
                                key={place_id}
                                id={optionId(index)}
                                // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role jsx-a11y/no-noninteractive-element-to-interactive-role lat:ignore
                                role="option"
                                aria-selected={index === activeIndex}
                                onClick={() => handleSelect(suggestion)()}
                                onMouseEnter={() => setActiveIndex(index)}
                                className={cn(
                                    "cursor-pointer px-3 py-2 text-sm",
                                    index === activeIndex ? "bg-accent/50" : "hover:bg-accent/50",
                                )}
                            >
                                <span className="font-semibold">{main_text}</span>{" "}
                                <span className="text-muted-foreground">{secondary_text}</span>
                            </li>
                        );
                    })}
                    <li
                        role="presentation"
                        aria-hidden="true"
                        className="flex items-center justify-between border-t border-border bg-muted/30 px-3 py-1.5 text-[11px] text-muted-foreground"
                        data-testid="osm-attribution"
                    >
                        <span>Search by Nominatim</span>
                        <span>© OpenStreetMap contributors</span>
                    </li>
                </ul>
            )}

            {errorMessage && (
                <p id={errorId} role="alert" className="text-sm font-semibold text-destructive">
                    {errorMessage}
                </p>
            )}
        </div>
    );
};

export default NominatimAddressAutocomplete;
