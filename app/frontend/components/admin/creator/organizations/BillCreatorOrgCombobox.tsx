import { TOrganizationOption } from "app/frontend/components/admin/creator/types";
import { Support } from "app/frontend/sway_constants";
import { Plus } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Input } from "app/frontend/components/ui/input";
import BillCreatorOrgSelectedChips from "app/frontend/components/admin/creator/organizations/BillCreatorOrgSelectedChips";

interface IProps {
    selected: TOrganizationOption[];
    availableOptions: TOrganizationOption[];
    onAppend: (option: TOrganizationOption) => void;
    onRemove: (value: number | string) => void;
}

const BillCreatorOrgCombobox: React.FC<IProps> = ({ selected, availableOptions, onAppend, onRemove }) => {
    const [query, setQuery] = useState<string>("");
    const [open, setOpen] = useState<boolean>(false);
    const containerRef = useRef<HTMLDivElement | null>(null);

    // @lat: [[bill-creator-organizations-panel#Why sessionCacheRef is written at the remove event, not via an effect]]
    const nextTempId = useRef<number>(-1);

    const selectedIds = useMemo(() => new Set(selected.map((o) => o.value)), [selected]);

    useEffect(() => {
        if (!open) return;
        const onDocClick = (e: MouseEvent) => {
            if (!containerRef.current) return;
            if (!containerRef.current.contains(e.target as Node)) {
                setOpen(false);
            }
        };
        document.addEventListener("mousedown", onDocClick);
        return () => document.removeEventListener("mousedown", onDocClick);
    }, [open]);

    const normalizedQuery = useMemo(() => query.replace(/\s+/g, " ").trim(), [query]);

    const filtered = useMemo(() => {
        const q = normalizedQuery.toLowerCase();
        const unselected = availableOptions.filter((o) => !selectedIds.has(o.value));
        if (!q) return unselected;
        return unselected.filter((o) => o.label.toLowerCase().includes(q));
    }, [availableOptions, selectedIds, normalizedQuery]);

    const canCreate = useMemo(() => {
        if (!normalizedQuery) return false;
        const lower = normalizedQuery.toLowerCase();
        const existsSelected = selected.some((o) => o.label.replace(/\s+/g, " ").trim().toLowerCase() === lower);
        const existsAvailable = availableOptions.some(
            (o) => o.label.replace(/\s+/g, " ").trim().toLowerCase() === lower,
        );
        return !existsSelected && !existsAvailable;
    }, [availableOptions, selected, normalizedQuery]);

    const appendOrganization = useCallback(
        (option: TOrganizationOption) => {
            onAppend(option);
            setQuery("");
            setOpen(false);
        },
        [onAppend],
    );

    const handleCreate = useCallback(() => {
        if (!normalizedQuery) return;
        appendOrganization({
            value: nextTempId.current--,
            label: normalizedQuery,
            summary: "",
            support: Support.For,
            icon_url: undefined,
        });
    }, [appendOrganization, normalizedQuery]);

    const onKeyDown = useCallback(
        (e: React.KeyboardEvent<HTMLInputElement>) => {
            if (e.key === "Enter") {
                e.preventDefault();
                if (filtered.length > 0) {
                    appendOrganization(filtered[0]);
                    return;
                }
                if (canCreate) {
                    handleCreate();
                }
            } else if (e.key === "Escape") {
                setOpen(false);
            }
        },
        [appendOrganization, canCreate, filtered, handleCreate],
    );

    return (
        <div ref={containerRef} className="relative flex flex-col gap-2">
            <BillCreatorOrgSelectedChips selected={selected} onRemove={onRemove} />

            <Input
                type="text"
                value={query}
                placeholder="Search or create an organization..."
                onChange={(e) => {
                    setQuery(e.target.value);
                    setOpen(true);
                }}
                onFocus={() => setOpen(true)}
                onKeyDown={onKeyDown}
            />

            {open && (filtered.length > 0 || canCreate) && (
                <div className="absolute top-full left-0 right-0 z-30 mt-1 max-h-64 overflow-auto rounded-xl border-neo border-border-strong bg-popover shadow-neo">
                    {filtered.map((option) => (
                        <button
                            key={`org-option-${option.value}`}
                            type="button"
                            onClick={() => appendOrganization(option)}
                            className="flex min-h-11 w-full items-center justify-between gap-2 px-3 py-2.5 text-left text-sm hover:bg-accent/15 focus-visible:bg-accent/20 outline-none sm:min-h-9"
                        >
                            <span>{option.label}</span>
                        </button>
                    ))}
                    {canCreate && (
                        <button
                            type="button"
                            onClick={handleCreate}
                            className="flex min-h-11 w-full items-center gap-2 border-t-neo border-border-soft px-3 py-2.5 text-left text-sm font-semibold hover:bg-accent/15 focus-visible:bg-accent/20 outline-none sm:min-h-9"
                        >
                            <Plus aria-hidden className="size-4" />
                            <span>Create &ldquo;{normalizedQuery}&rdquo;</span>
                        </button>
                    )}
                </div>
            )}
        </div>
    );
};

export default BillCreatorOrgCombobox;
