"use client";

import * as React from "react";
import { Popover as PopoverPrimitive } from "radix-ui";
import { Check, ChevronsUpDown, Search } from "lucide-react";

import { cn } from "@/lib/utils";
import { filterComboboxOptions, type ComboboxOption } from "@/components/ui/combobox-filter";

export type { ComboboxOption };

function firstEnabledIndex(items: ComboboxOption[]): number {
    return items.findIndex((item) => !item.disabled);
}

function lastEnabledIndex(items: ComboboxOption[]): number {
    for (let i = items.length - 1; i >= 0; i--) {
        if (!items[i]?.disabled) return i;
    }
    return -1;
}

interface ComboboxProps {
    value: string | null;
    onValueChange: (value: string) => void;
    options: ComboboxOption[];
    /** Always shown first and never filtered out (e.g. a "New Bill" sentinel). */
    pinnedOption?: ComboboxOption;
    /** Trigger text when nothing is selected. */
    placeholder?: string;
    searchPlaceholder?: string;
    emptyText?: string;
    id?: string;
    disabled?: boolean;
    /** Merged onto the trigger button. */
    className?: string;
    contentClassName?: string;
    "aria-label"?: string;
    "aria-labelledby"?: string;
    "aria-invalid"?: boolean;
    "aria-describedby"?: string;
    "data-testid"?: string;
}

// @lat: [[combobox-primitive-design#Why filterComboboxOptions is a separate pure function]]
function Combobox({
    value,
    onValueChange,
    options,
    pinnedOption,
    placeholder = "Select…",
    searchPlaceholder = "Search…",
    emptyText = "No results.",
    id,
    disabled,
    className,
    contentClassName,
    "aria-label": ariaLabel,
    "aria-labelledby": ariaLabelledby,
    "aria-invalid": ariaInvalid,
    "aria-describedby": ariaDescribedby,
    "data-testid": dataTestid,
}: ComboboxProps) {
    const [open, setOpen] = React.useState(false);
    const [query, setQuery] = React.useState("");
    const [activeIndex, setActiveIndex] = React.useState(0);

    const baseId = React.useId();
    const listboxId = `${baseId}-listbox`;
    const valueId = `${baseId}-value`;
    const inputRef = React.useRef<HTMLInputElement>(null);
    const optionRefs = React.useRef<Array<HTMLLIElement | null>>([]);

    const defaultVisible = React.useMemo(
        () => (pinnedOption ? [pinnedOption, ...options] : options),
        [pinnedOption, options],
    );
    const filtered = React.useMemo(() => filterComboboxOptions(options, query), [options, query]);
    // Pinned sentinel is always first and survives filtering.
    const visible = React.useMemo(
        () => (pinnedOption ? [pinnedOption, ...filtered] : filtered),
        [pinnedOption, filtered],
    );

    const selectedLabel = React.useMemo(() => {
        return defaultVisible.find((option) => option.value === value)?.label ?? null;
    }, [defaultVisible, value]);

    const rawClamped = visible.length && activeIndex >= 0 ? Math.min(activeIndex, visible.length - 1) : -1;
    const clampedActive = rawClamped >= 0 && visible[rawClamped]?.disabled ? firstEnabledIndex(visible) : rawClamped;
    const hasActiveOption = clampedActive >= 0 && !visible[clampedActive]?.disabled;
    const activeId = hasActiveOption ? `${baseId}-opt-${clampedActive}` : undefined;

    const openCombobox = React.useCallback(() => {
        setQuery("");
        setOpen(true);
        const selectedIndex = defaultVisible.findIndex((o) => o.value === value && !o.disabled);
        setActiveIndex(selectedIndex >= 0 ? selectedIndex : firstEnabledIndex(defaultVisible));
    }, [defaultVisible, value]);

    const commit = (option: ComboboxOption | undefined) => {
        if (!option || option.disabled) return;
        onValueChange(option.value);
        setOpen(false);
    };

    const moveActive = (delta: number) => {
        if (!visible.length) return;
        const hasEnabled = visible.some((o) => !o.disabled);
        if (!hasEnabled) return;
        let next = clampedActive >= 0 ? clampedActive : delta > 0 ? -1 : 0;
        for (let i = 0; i < visible.length; i++) {
            next = (next + delta + visible.length) % visible.length;
            if (!visible[next]?.disabled) {
                setActiveIndex(next);
                optionRefs.current[next]?.scrollIntoView({ block: "nearest" });
                break;
            }
        }
    };

    const onInputKeyDown = (event: React.KeyboardEvent<HTMLElement>) => {
        switch (event.key) {
            case "ArrowDown":
                event.preventDefault();
                event.stopPropagation();
                moveActive(1);
                break;
            case "ArrowUp":
                event.preventDefault();
                event.stopPropagation();
                moveActive(-1);
                break;
            case "Home": {
                event.preventDefault();
                event.stopPropagation();
                const idx = firstEnabledIndex(visible);
                setActiveIndex(idx);
                if (idx >= 0) {
                    optionRefs.current[idx]?.scrollIntoView({ block: "nearest" });
                }
                break;
            }
            case "End": {
                event.preventDefault();
                event.stopPropagation();
                const idx = lastEnabledIndex(visible);
                setActiveIndex(idx);
                if (idx >= 0) {
                    optionRefs.current[idx]?.scrollIntoView({ block: "nearest" });
                }
                break;
            }
            case "Enter":
                event.preventDefault();
                event.stopPropagation();
                if (hasActiveOption) {
                    commit(visible[clampedActive]);
                }
                break;
            // Escape is handled by Radix Popover (closes + restores focus).
        }
    };

    return (
        <PopoverPrimitive.Root
            open={open}
            onOpenChange={(next) => {
                if (next) {
                    openCombobox();
                } else {
                    setOpen(false);
                }
            }}
        >
            <PopoverPrimitive.Trigger asChild>
                <button
                    type="button"
                    id={id}
                    // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role -- WAI-ARIA combobox pattern (custom-rendered, type-ahead filtering); no native HTML element provides this behavior.
                    role="combobox"
                    aria-expanded={open}
                    aria-haspopup="listbox"
                    aria-controls={open ? listboxId : undefined}
                    aria-label={ariaLabel}
                    aria-labelledby={ariaLabelledby ? `${ariaLabelledby} ${valueId}` : undefined}
                    aria-describedby={ariaDescribedby}
                    aria-invalid={ariaInvalid ? "true" : undefined}
                    data-testid={dataTestid}
                    data-slot="combobox-trigger"
                    disabled={disabled}
                    onKeyDown={(event) => {
                        if (!open && !disabled && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
                            event.preventDefault();
                            openCombobox();
                        }
                    }}
                    className={cn(
                        "flex h-11 w-full items-center justify-between gap-2 rounded-xl border-neo border-border-strong bg-input px-3 py-2 text-base shadow-neo outline-none transition-[color,box-shadow]",
                        "focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50",
                        "disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50",
                        "md:text-sm",
                        className,
                    )}
                >
                    <span
                        id={valueId}
                        className={cn("line-clamp-1 text-left", !selectedLabel && "text-muted-foreground")}
                    >
                        {selectedLabel ?? placeholder}
                    </span>
                    <ChevronsUpDown className="size-4 shrink-0 text-muted-icon" aria-hidden />
                </button>
            </PopoverPrimitive.Trigger>
            <PopoverPrimitive.Portal>
                <PopoverPrimitive.Content
                    align="start"
                    sideOffset={4}
                    data-slot="combobox-content"
                    onOpenAutoFocus={(event) => {
                        // Land focus on the search field, not the first option.
                        event.preventDefault();
                        inputRef.current?.focus();
                    }}
                    onCloseAutoFocus={() => {
                        setQuery("");
                    }}
                    className={cn(
                        "z-50 w-(--radix-popover-trigger-width) overflow-hidden rounded-xl border border-foreground bg-popover text-popover-foreground shadow-lg",
                        "data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:animate-in data-[state=open]:fade-in-0",
                        contentClassName,
                    )}
                >
                    <div className="flex items-center gap-2 border-b border-border-soft px-3">
                        <Search className="size-4 shrink-0 text-muted-icon" aria-hidden />
                        <input
                            ref={inputRef}
                            data-slot="combobox-input"
                            value={query}
                            onChange={(event) => {
                                setQuery(event.target.value);
                                setActiveIndex(0);
                            }}
                            onKeyDown={onInputKeyDown}
                            placeholder={searchPlaceholder}
                            aria-label={searchPlaceholder}
                            aria-autocomplete="list"
                            aria-controls={listboxId}
                            aria-activedescendant={activeId}
                            autoComplete="off"
                            autoCorrect="off"
                            spellCheck={false}
                            className="h-10 w-full bg-transparent py-2 text-sm outline-none placeholder:text-muted-foreground"
                        />
                    </div>
                    <ul
                        id={listboxId}
                        // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role jsx-a11y/no-noninteractive-element-to-interactive-role -- WAI-ARIA combobox pattern (custom-rendered, type-ahead filtering); no native HTML element provides this behavior.
                        role="listbox"
                        tabIndex={-1}
                        onKeyDown={onInputKeyDown}
                        className="max-h-72 overflow-y-auto p-1"
                    >
                        {visible.length === 0 ? (
                            <li role="presentation" className="px-2 py-6 text-center text-sm text-muted-foreground">
                                {emptyText}
                            </li>
                        ) : (
                            visible.map((option, index) => {
                                const isActive = hasActiveOption && index === clampedActive;
                                const isSelected = option.value === value;
                                return (
                                    // oxlint-disable-next-line jsx-a11y/click-events-have-key-events -- WAI-ARIA combobox pattern; keyboard navigation handled at parent combobox trigger level
                                    <li
                                        key={option.value}
                                        id={`${baseId}-opt-${index}`}
                                        ref={(el) => {
                                            optionRefs.current[index] = el;
                                        }}
                                        // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role jsx-a11y/no-noninteractive-element-to-interactive-role -- WAI-ARIA combobox pattern (custom-rendered, type-ahead filtering); no native HTML element provides this behavior.
                                        role="option"
                                        tabIndex={-1}
                                        aria-selected={isSelected}
                                        aria-disabled={option.disabled || undefined}
                                        data-active={isActive || undefined}
                                        data-highlighted={isActive ? "" : undefined}
                                        onMouseMove={() => {
                                            if (!option.disabled) {
                                                setActiveIndex(index);
                                            }
                                        }}
                                        onFocus={() => {
                                            if (!option.disabled) {
                                                setActiveIndex(index);
                                            }
                                        }}
                                        // oxlint-disable-next-line jsx-a11y/click-events-have-key-events -- WAI-ARIA combobox pattern (custom-rendered, type-ahead filtering); keyboard selection handled by parent combobox trigger.
                                        onClick={() => commit(option)}
                                        className={cn(
                                            "relative flex cursor-pointer items-start gap-2 rounded-md py-1.5 pr-8 pl-2 text-sm outline-none",
                                            isActive && "bg-accent/20",
                                            option.disabled && "pointer-events-none opacity-50",
                                        )}
                                    >
                                        <span className="min-w-0 flex-1">{option.node ?? option.label}</span>
                                        {isSelected && (
                                            <span className="absolute right-2 top-2 flex size-4 items-center justify-center">
                                                <Check className="size-4" strokeWidth={3} aria-hidden />
                                            </span>
                                        )}
                                    </li>
                                );
                            })
                        )}
                    </ul>
                </PopoverPrimitive.Content>
            </PopoverPrimitive.Portal>
        </PopoverPrimitive.Root>
    );
}

export { Combobox };
