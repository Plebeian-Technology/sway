// @lat: [[locale-extension#Nominatim geographic configuration]]
import { useJsApiLoader } from "@react-google-maps/api";
import type { InertiaFormProps } from "@inertiajs/react";
import { useCallback, useId, useState } from "react";
import { sway } from "sway";

import { useAddressAutocomplete } from "app/frontend/hooks/useAddressAutocomplete";
import { Input } from "app/frontend/components/ui/input";
import { Label } from "app/frontend/components/ui/label";
import { cn } from "app/frontend/lib/utils";

interface IProps<T, TForm extends Partial<sway.IAddress> = Partial<sway.IAddress>> {
    // @lat: [[address-autocomplete-hook-design#Why form is typed loosely on AddressAutocomplete's props]]
    form: InertiaFormProps<TForm>;
    field: sway.IFormField<T>;
    setLoading: (l: boolean) => void;
}

const GOOGLE_MAPS_LIBRARIES = ["places"] as ["places"];

function Autocomplete<T, TForm extends Partial<sway.IAddress> = Partial<sway.IAddress>>({
    form,
    field,
    setLoading,
}: IProps<T, TForm>) {
    const { value, status, suggestions, loading, handleInput, handleSelect, clearSuggestions } = useAddressAutocomplete(
        form,
        setLoading,
    );

    const [activeIndex, setActiveIndex] = useState(-1);
    const listboxId = useId();
    const optionId = (index: number) => `${listboxId}-option-${index}`;
    const isOpen = status === "OK" && suggestions.length > 0;

    // @lat: [[address-autocomplete-hook-design#Why form is typed loosely on AddressAutocomplete's props]]
    const formErrors = form.errors as Record<string, string | undefined>;
    const errorMessage = formErrors[field.name as string] ?? Object.values(formErrors)[0];
    const errorId = `${field.name}-error`;

    // @lat: [[address-autocomplete-hook-design#Why the AddressAutocomplete component resets state in an event handler, not useEffect]]
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

    return (
        <div className="space-y-2">
            <Label htmlFor={field.name}>{field.label}</Label>
            <Input
                id={field.name}
                key={field.name}
                name={field.name}
                autoComplete="off"
                value={value}
                onChange={handleInputChange}
                onKeyDown={handleKeyDown}
                required={field.isRequired}
                // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role -- WAI-ARIA combobox pattern (custom-rendered, type-ahead filtering); no native HTML element provides this behavior.
                role="combobox"
                aria-expanded={isOpen}
                aria-controls={isOpen ? listboxId : undefined}
                aria-autocomplete="list"
                aria-activedescendant={activeIndex >= 0 ? optionId(activeIndex) : undefined}
                aria-invalid={Boolean(errorMessage)}
                aria-describedby={errorMessage ? errorId : undefined}
                disabled={field.disabled || loading}
                placeholder="1 W Elm St"
            />
            {isOpen && (
                <ul
                    id={listboxId}
                    // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role jsx-a11y/no-noninteractive-element-to-interactive-role -- WAI-ARIA combobox pattern (custom-rendered, type-ahead filtering); no native HTML element provides this behavior.
                    role="listbox"
                    className="mt-1 divide-y divide-border rounded-xl border-neo border-border bg-card shadow-neo"
                >
                    {suggestions.map((suggestion, index) => {
                        const {
                            place_id,
                            structured_formatting: { main_text, secondary_text },
                        } = suggestion;
                        return (
                            // oxlint-disable-next-line jsx-a11y/click-events-have-key-events -- WAI-ARIA combobox pattern; keyboard navigation handled at parent combobox trigger level
                            <li
                                key={place_id}
                                id={optionId(index)}
                                // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role jsx-a11y/no-noninteractive-element-to-interactive-role -- WAI-ARIA combobox pattern (custom-rendered, type-ahead filtering); no native HTML element provides this behavior.
                                role="option"
                                aria-selected={index === activeIndex}
                                // oxlint-disable-next-line jsx-a11y/click-events-have-key-events -- WAI-ARIA combobox pattern (custom-rendered, type-ahead filtering); keyboard selection handled by parent combobox trigger.
                                onClick={handleSelect(suggestion)}
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
                </ul>
            )}
            {errorMessage && (
                <p id={errorId} role="alert" className="text-sm font-semibold text-destructive">
                    {errorMessage}
                </p>
            )}
        </div>
    );
}

// @lat: [[locale-extension#Nominatim geographic configuration]]
export default function AddressAutocomplete<T>(props: IProps<T>) {
    const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string;
    if (!apiKey) {
        console.error(
            "Google Maps API key is not set. Please set VITE_GOOGLE_MAPS_API_KEY in your environment variables.",
        );
    }
    const { isLoaded } = useJsApiLoader({
        googleMapsApiKey: apiKey,
        libraries: GOOGLE_MAPS_LIBRARIES,
        preventGoogleFontsLoading: true,
    });

    if (isLoaded) return <Autocomplete {...props} />;
    return (
        <div
            className="h-11 w-full animate-pulse rounded-xl border-neo border-border-strong bg-input"
            data-testid="address-autocomplete-skeleton"
        />
    );
}
