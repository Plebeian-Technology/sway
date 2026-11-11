import { ChevronsUpDown, Search } from "lucide-react";
import { Popover as PopoverPrimitive } from "radix-ui";
import { useMemo, useState } from "react";

import { cn } from "@/lib/utils";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import "app/frontend/components/bill/list-layouts/category-multi-select.css";

interface IProps {
    id: string;
    allCategories: readonly string[];
    selectedCategories: string[];
    onToggleCategory: (category: string) => void;
    onClearCategories: () => void;
    triggerClassName?: string;
    labelClassName?: string;
}

// @lat: [[bills-category-filter#One control, four themes]]
const CategoryMultiSelect: React.FC<IProps> = ({
    id,
    allCategories,
    selectedCategories,
    onToggleCategory,
    onClearCategories,
    triggerClassName,
    labelClassName,
}) => {
    const [open, setOpen] = useState(false);
    const [query, setQuery] = useState("");

    const labelId = `${id}-label`;
    const valueId = `${id}-value`;

    const visible = useMemo(() => {
        const needle = query.trim().toLowerCase();
        return needle ? allCategories.filter((category) => category.toLowerCase().includes(needle)) : allCategories;
    }, [allCategories, query]);

    const summary = selectedCategories.length ? selectedCategories.join(", ") : PARITY_COPY.bills.allCategoriesLabel;

    return (
        <>
            <span id={labelId} className={labelClassName}>
                {PARITY_COPY.bills.categoriesLabel}
            </span>
            <PopoverPrimitive.Root
                open={open}
                onOpenChange={(next) => {
                    setOpen(next);
                    if (!next) setQuery("");
                }}
            >
                <PopoverPrimitive.Trigger asChild>
                    <button
                        type="button"
                        id={id}
                        aria-haspopup="dialog"
                        aria-expanded={open}
                        aria-labelledby={`${labelId} ${valueId}`}
                        data-testid="bills-category-filter"
                        className={cn("cat-filter__trigger", triggerClassName)}
                    >
                        <span id={valueId} className="cat-filter__value">
                            {summary}
                        </span>
                        <ChevronsUpDown className="cat-filter__chevron" aria-hidden />
                    </button>
                </PopoverPrimitive.Trigger>
                <PopoverPrimitive.Portal>
                    <PopoverPrimitive.Content
                        align="start"
                        sideOffset={4}
                        aria-labelledby={labelId}
                        className="cat-filter__panel w-(--radix-popover-trigger-width)"
                    >
                        <div className="cat-filter__search">
                            <Search className="cat-filter__search-icon" aria-hidden />
                            <input
                                type="search"
                                value={query}
                                onChange={(event) => setQuery(event.target.value)}
                                placeholder={PARITY_COPY.bills.categoryFilterPlaceholder}
                                aria-label={PARITY_COPY.bills.categoryFilterPlaceholder}
                                autoComplete="off"
                                spellCheck={false}
                                className="cat-filter__search-input"
                            />
                        </div>

                        <ul className="cat-filter__options">
                            {visible.length === 0 ? (
                                <li className="cat-filter__empty">{PARITY_COPY.bills.noCategoriesFound}</li>
                            ) : (
                                visible.map((category) => (
                                    <li key={category}>
                                        <label className="cat-filter__option">
                                            <input
                                                type="checkbox"
                                                className="cat-filter__checkbox"
                                                checked={selectedCategories.includes(category)}
                                                onChange={() => onToggleCategory(category)}
                                            />
                                            <span>{category}</span>
                                        </label>
                                    </li>
                                ))
                            )}
                        </ul>

                        {selectedCategories.length > 0 && (
                            <button type="button" className="cat-filter__clear" onClick={onClearCategories}>
                                {PARITY_COPY.bills.clearCategoriesLabel}
                            </button>
                        )}
                    </PopoverPrimitive.Content>
                </PopoverPrimitive.Portal>
            </PopoverPrimitive.Root>
        </>
    );
};

export default CategoryMultiSelect;
