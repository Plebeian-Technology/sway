import { router } from "@inertiajs/react";
import { LoaderCircle } from "lucide-react";
import React, { useEffect, useMemo, useRef, useState } from "react";
import type { sway } from "sway";

import { Badge } from "app/frontend/components/ui/badge";
import { Button } from "app/frontend/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "app/frontend/components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "app/frontend/components/ui/tabs";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

export type IPublicTestimonyLetter = sway.IPublicTestimonyLetter;
export type IPublicTestimonyCounts = sway.IPublicTestimonyCounts;

export type TStanceFilter = "all" | "support" | "oppose" | "neutral";

export interface IProps {
    isOpen?: boolean;
    open?: boolean;
    onClose?: () => void;
    onOpenChange?: (open: boolean) => void;
    counts?: IPublicTestimonyCounts | null;
    letters?: IPublicTestimonyLetter[] | null;
    billTitle?: string;
    initialFilter?: TStanceFilter;
    initialStance?: TStanceFilter;
    billId?: number;
    canOverrideStance?: boolean;
}

const PAGE_SIZE = 10;

const getStanceBadgeTone = (stance: "support" | "oppose" | "neutral") => {
    switch (stance) {
        case "support":
            return "success" as const;
        case "oppose":
            return "danger" as const;
        case "neutral":
            return "neutral" as const;
        default:
            return "neutral" as const;
    }
};

const getStanceBadgeLabel = (stance: "support" | "oppose" | "neutral") => {
    switch (stance) {
        case "support":
            return PARITY_COPY.publicTestimony.modal.supportBadge;
        case "oppose":
            return PARITY_COPY.publicTestimony.modal.opposeBadge;
        case "neutral":
            return PARITY_COPY.publicTestimony.modal.neutralBadge;
        default:
            return PARITY_COPY.publicTestimony.modal.neutralBadge;
    }
};

interface IModalBodyProps {
    counts?: IPublicTestimonyCounts | null;
    letters?: IPublicTestimonyLetter[] | null;
    billTitle?: string;
    initialFilter: TStanceFilter;
    billId?: number;
    canOverrideStance?: boolean;
}

const BrowseTestimonyModalBody: React.FC<IModalBodyProps> = ({
    counts,
    letters,
    billTitle,
    initialFilter,
    billId,
    canOverrideStance,
}) => {
    const [activeTab, setActiveTab] = useState<TStanceFilter>(initialFilter);
    const [currentPage, setCurrentPage] = useState(1);
    const [fetchSettled, setFetchSettled] = useState(false);
    const hasRequestedRef = useRef(false);

    const handleOverrideStance = (position: number, nextStance: "support" | "oppose" | "neutral") => {
        if (!billId || !canOverrideStance) return;
        router.patch(
            `/bills/${billId}/testimony_letter_stance`,
            { position, stance: nextStance },
            {
                preserveScroll: true,
                preserveState: true,
                only: ["public_testimony_counts", "public_testimony_letters", "flash"],
            },
        );
    };

    const handleRemoveLetter = (position: number) => {
        if (!billId || !canOverrideStance) return;
        router.patch(
            `/bills/${billId}/testimony_letter_stance`,
            { position, excluded: true },
            {
                preserveScroll: true,
                preserveState: true,
                only: ["public_testimony_counts", "public_testimony_letters", "flash"],
            },
        );
    };

    const totalCount = counts?.total ?? letters?.length ?? 0;
    const supportCount = counts?.support ?? letters?.filter((l) => l.stance === "support").length ?? 0;
    const opposeCount = counts?.oppose ?? letters?.filter((l) => l.stance === "oppose").length ?? 0;
    const neutralCount = counts?.neutral ?? letters?.filter((l) => l.stance === "neutral").length ?? 0;

    const hasLoadedLetters =
        Array.isArray(letters) &&
        (counts === undefined || counts === null
            ? letters.length > 0
            : letters.length === counts.total || fetchSettled);
    const shouldFetch = !hasLoadedLetters && (counts ? counts.total > 0 : true);

    useEffect(() => {
        if (shouldFetch && !hasRequestedRef.current) {
            hasRequestedRef.current = true;
            router.reload({
                only: ["public_testimony_letters"],
                onFinish: () => setFetchSettled(true),
                onError: () => setFetchSettled(true),
            });
        }
    }, [shouldFetch]);

    const handleTabChange = (tab: TStanceFilter) => {
        setActiveTab(tab);
        setCurrentPage(1);
    };

    const filteredLetters = useMemo(() => {
        if (!letters) return [];
        if (activeTab === "all") return letters;
        return letters.filter((letter) => letter.stance === activeTab);
    }, [letters, activeTab]);

    const totalPages = Math.max(1, Math.ceil(filteredLetters.length / PAGE_SIZE));
    const safePage = Math.min(currentPage, totalPages);
    const startIndex = (safePage - 1) * PAGE_SIZE;
    const paginatedLetters = filteredLetters.slice(startIndex, startIndex + PAGE_SIZE);

    const isFetching = shouldFetch && !fetchSettled;

    return (
        <DialogContent className="flex max-h-[85vh] w-full max-w-2xl flex-col gap-4 overflow-hidden p-6">
            <DialogHeader className="space-y-1 border-b border-border-soft pb-3 text-left">
                <DialogTitle className="text-xl font-bold">{PARITY_COPY.publicTestimony.modal.title}</DialogTitle>
                {billTitle && (
                    <p className="truncate text-xs font-medium text-muted-foreground" title={billTitle}>
                        {billTitle}
                    </p>
                )}
                <DialogDescription className="text-sm text-muted-foreground">
                    {PARITY_COPY.publicTestimony.modal.subtitle(totalCount)}
                </DialogDescription>
            </DialogHeader>

            <Tabs
                value={activeTab}
                onValueChange={(val) => handleTabChange(val as TStanceFilter)}
                className="flex min-h-0 w-full flex-1 flex-col"
            >
                <TabsList className="w-full">
                    <TabsTrigger
                        value="all"
                        className="flex-1"
                        data-testid="tab-all"
                        onClick={() => handleTabChange("all")}
                    >
                        {PARITY_COPY.publicTestimony.modal.allTab} ({totalCount})
                    </TabsTrigger>
                    <TabsTrigger
                        value="support"
                        className="flex-1"
                        data-testid="tab-support"
                        onClick={() => handleTabChange("support")}
                    >
                        {PARITY_COPY.publicTestimony.modal.supportTab} ({supportCount})
                    </TabsTrigger>
                    <TabsTrigger
                        value="oppose"
                        className="flex-1"
                        data-testid="tab-oppose"
                        onClick={() => handleTabChange("oppose")}
                    >
                        {PARITY_COPY.publicTestimony.modal.opposeTab} ({opposeCount})
                    </TabsTrigger>
                    <TabsTrigger
                        value="neutral"
                        className="flex-1"
                        data-testid="tab-neutral"
                        onClick={() => handleTabChange("neutral")}
                    >
                        {PARITY_COPY.publicTestimony.modal.neutralTab} ({neutralCount})
                    </TabsTrigger>
                </TabsList>

                <TabsContent value={activeTab} className="mt-0 flex min-h-0 flex-1 flex-col outline-none">
                    {isFetching ? (
                        <div
                            className="flex flex-col items-center justify-center gap-3 py-12 text-muted-foreground"
                            data-testid="loading-state"
                        >
                            <LoaderCircle className="size-6 animate-spin text-muted-foreground" aria-hidden="true" />
                            <p className="text-sm">{PARITY_COPY.publicTestimony.modal.loading}</p>
                        </div>
                    ) : filteredLetters.length === 0 ? (
                        <div
                            className="flex flex-col items-center justify-center py-12 text-center text-muted-foreground"
                            data-testid="empty-state"
                        >
                            <p className="text-sm">{PARITY_COPY.publicTestimony.modal.empty}</p>
                        </div>
                    ) : (
                        <>
                            <div className="mt-4 flex-1 space-y-4 overflow-y-auto pr-1" data-testid="letters-list">
                                {paginatedLetters.map((letter) => (
                                    <div
                                        key={`${letter.position}-${letter.label}`}
                                        className="space-y-2 rounded-lg border-neo border-border-strong bg-card p-4 shadow-sm"
                                        data-testid={`testimony-letter-${letter.position}`}
                                    >
                                        <div className="flex items-center justify-between gap-2">
                                            <h4 className="text-sm font-semibold text-foreground">{letter.label}</h4>
                                            <div className="flex items-center gap-2">
                                                {canOverrideStance && billId ? (
                                                    <>
                                                        <select
                                                            aria-label={`Stance for ${letter.label}`}
                                                            data-testid={`select-letter-stance-${letter.position}`}
                                                            value={letter.stance}
                                                            onChange={(e) =>
                                                                handleOverrideStance(
                                                                    letter.position,
                                                                    e.target.value as "support" | "oppose" | "neutral",
                                                                )
                                                            }
                                                            className="rounded-md border border-border-strong bg-surface-2 px-2 py-1 text-xs font-medium text-foreground focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
                                                        >
                                                            <option value="support">
                                                                {PARITY_COPY.publicTestimony.modal.supportBadge}
                                                            </option>
                                                            <option value="oppose">
                                                                {PARITY_COPY.publicTestimony.modal.opposeBadge}
                                                            </option>
                                                            <option value="neutral">
                                                                {PARITY_COPY.publicTestimony.modal.neutralBadge}
                                                            </option>
                                                        </select>
                                                        <button
                                                            type="button"
                                                            aria-label={`Remove ${letter.label}`}
                                                            data-testid={`remove-letter-${letter.position}`}
                                                            onClick={() => handleRemoveLetter(letter.position)}
                                                            className="rounded-md border border-destructive/40 bg-destructive/10 px-2 py-1 text-xs font-medium text-destructive hover:bg-destructive/20 focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
                                                        >
                                                            Remove
                                                        </button>
                                                    </>
                                                ) : null}
                                                <Badge variant="stamp" tone={getStanceBadgeTone(letter.stance)}>
                                                    {getStanceBadgeLabel(letter.stance)}
                                                </Badge>
                                            </div>
                                        </div>
                                        <p className="break-words text-sm leading-relaxed whitespace-pre-wrap text-foreground">
                                            {letter.body_text}
                                        </p>
                                    </div>
                                ))}
                            </div>

                            <div className="mt-2 flex items-center justify-between border-t border-border-soft pt-4">
                                <Button
                                    type="button"
                                    variant="outline"
                                    size="sm"
                                    onClick={() => setCurrentPage(Math.max(1, safePage - 1))}
                                    disabled={safePage <= 1}
                                    data-testid="pagination-prev"
                                >
                                    {PARITY_COPY.publicTestimony.modal.previousPage}
                                </Button>
                                <span className="text-sm text-muted-foreground" data-testid="pagination-indicator">
                                    {PARITY_COPY.publicTestimony.modal.pageIndicator(safePage, totalPages)}
                                </span>
                                <Button
                                    type="button"
                                    variant="outline"
                                    size="sm"
                                    onClick={() => setCurrentPage(Math.min(totalPages, safePage + 1))}
                                    disabled={safePage >= totalPages}
                                    data-testid="pagination-next"
                                >
                                    {PARITY_COPY.publicTestimony.modal.nextPage}
                                </Button>
                            </div>
                        </>
                    )}
                </TabsContent>
            </Tabs>
        </DialogContent>
    );
};

// @lat: [[testimony-letters#Browsing constituent testimony in the modal]]
const BrowseTestimonyModal: React.FC<IProps> = ({
    isOpen,
    open,
    onClose,
    onOpenChange,
    counts,
    letters,
    billTitle,
    initialFilter,
    initialStance,
    billId,
    canOverrideStance,
}) => {
    const resolvedOpen = isOpen ?? open ?? false;
    const resolvedFilter = initialFilter ?? initialStance ?? "all";

    return (
        <Dialog
            open={resolvedOpen}
            onOpenChange={(nextOpen) => {
                onOpenChange?.(nextOpen);
                if (!nextOpen) onClose?.();
            }}
        >
            {resolvedOpen && (
                <BrowseTestimonyModalBody
                    key={`modal-${billTitle ?? ""}-${resolvedFilter}`}
                    counts={counts}
                    letters={letters}
                    billTitle={billTitle}
                    initialFilter={resolvedFilter}
                    billId={billId}
                    canOverrideStance={canOverrideStance}
                />
            )}
        </Dialog>
    );
};

export default BrowseTestimonyModal;
