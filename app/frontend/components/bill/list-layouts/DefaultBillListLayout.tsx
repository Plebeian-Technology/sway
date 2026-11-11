import { Deferred } from "@inertiajs/react";
import { ChevronDown } from "lucide-react";
import { useState } from "react";

import { cn } from "@/lib/utils";
import BillCard from "app/frontend/components/lists/BillCard";
import { Button } from "app/frontend/components/ui/button";
import { Label } from "app/frontend/components/ui/label";
import { NEO_SELECT_CLASS } from "app/frontend/components/ui/LocaleSelect";
import SwayLocalePicker from "app/frontend/components/locales/SwayLocalePicker";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { sway } from "sway";

import BillsSearchInput from "app/frontend/components/bill/list-layouts/BillsSearchInput";
import BillsSessionSelect from "app/frontend/components/bill/list-layouts/BillsSessionSelect";
import BillsSortSelect from "app/frontend/components/bill/list-layouts/BillsSortSelect";
import CategoryMultiSelect from "app/frontend/components/bill/list-layouts/CategoryMultiSelect";
import {
    BILLS_LOAD_MORE_LABEL,
    BILLS_LOADING_MORE_LABEL,
    BILLS_MORE_OPTIONS_LABEL,
    BILLS_SEARCH_LABEL,
    BILLS_SESSION_LABEL,
    BILLS_SORT_LABEL,
    type BillListLayoutProps,
} from "app/frontend/components/bill/list-layouts/types";

const FILTER_EYEBROW = "text-xs font-black uppercase tracking-[0.18em] text-muted-foreground";

const DefaultBillListLayout: React.FC<BillListLayoutProps> = ({
    bills,
    formattedSwayLocaleName,
    localeOptions,
    selectedSwayLocaleId,
    onLocaleChange,
    allCategories,
    selectedCategories,
    onToggleCategory,
    onClearCategories,
    hasMoreBills,
    isLoadingMoreBills,
    onLoadMoreBills,
    sortValue,
    onSortChange,
    searchValue,
    onSearchChange,
    listMode = "all_bills",
    legislativeSessions = [],
    selectedLegislativeSessionId,
    onLegislativeSessionChange,
}) => {
    const [moreOptionsOpen, setMoreOptionsOpen] = useState(false);
    const showSessionSelect = listMode !== "past_bills_of_the_month" && legislativeSessions.length > 0;
    const heading =
        listMode === "past_bills_of_the_month"
            ? PARITY_COPY.bills.pastBillsOfTheMonthTitle
            : PARITY_COPY.bills.allBillsTitle;

    return (
        <div className="space-y-6">
            <h1 className="text-2xl font-black">{heading}</h1>

            <div className="space-y-4 rounded-xl border border-border bg-surface-2 p-4">
                {/* @lat: [[bill-list-layout-props-contract#BillListLayoutProps contract]] */}
                {/* @lat: [[bills-filter-header#Why the fields are ordered twice]] */}
                <div className="flex flex-wrap gap-3">
                    <div className="w-full space-y-1.5 md:order-1 md:w-auto md:min-w-0 md:flex-1">
                        <Label htmlFor="v2-bills-locale" className={FILTER_EYEBROW}>
                            Locale
                        </Label>
                        <SwayLocalePicker
                            id="v2-bills-locale"
                            options={localeOptions}
                            value={selectedSwayLocaleId}
                            onChange={onLocaleChange}
                        />
                    </div>
                    <div className="w-full space-y-1.5 md:order-4 md:w-auto md:min-w-0 md:flex-1">
                        <Label htmlFor="v2-bills-search" className={FILTER_EYEBROW}>
                            {BILLS_SEARCH_LABEL}
                        </Label>
                        <BillsSearchInput
                            id="v2-bills-search"
                            className={cn(NEO_SELECT_CLASS, "cursor-text")}
                            value={searchValue}
                            onChange={onSearchChange}
                        />
                    </div>
                    {/* @lat: [[bills-filter-header#Why sort and categories collapse only on mobile]] */}
                    <button
                        type="button"
                        aria-expanded={moreOptionsOpen}
                        aria-controls="v2-bills-more-options"
                        onClick={() => setMoreOptionsOpen((open) => !open)}
                        data-testid="btn-bills-more-options"
                        className="flex w-full cursor-pointer items-center justify-between gap-2 border-t border-border pt-3 text-left hover:text-primary focus-visible:ring-2 focus-visible:ring-ring/50 md:hidden"
                    >
                        <span className={FILTER_EYEBROW}>{BILLS_MORE_OPTIONS_LABEL}</span>
                        <ChevronDown
                            className={cn(
                                "size-4 shrink-0 text-muted-icon transition-transform duration-normal",
                                moreOptionsOpen && "rotate-180",
                            )}
                            aria-hidden
                        />
                    </button>
                    <div
                        id="v2-bills-more-options"
                        className={cn("w-full flex-col gap-3 md:contents", moreOptionsOpen ? "flex" : "hidden")}
                    >
                        {showSessionSelect && (
                            <div className="space-y-1.5 md:order-2 md:w-[220px]">
                                <Label htmlFor="v2-bills-session" className={FILTER_EYEBROW}>
                                    {BILLS_SESSION_LABEL}
                                </Label>
                                <BillsSessionSelect
                                    id="v2-bills-session"
                                    className={NEO_SELECT_CLASS}
                                    sessions={legislativeSessions}
                                    value={selectedLegislativeSessionId}
                                    onChange={onLegislativeSessionChange}
                                />
                            </div>
                        )}
                        <div className="space-y-1.5 md:order-3 md:w-[200px]">
                            <Label htmlFor="v2-bills-sort" className={FILTER_EYEBROW}>
                                {BILLS_SORT_LABEL}
                            </Label>
                            <BillsSortSelect
                                id="v2-bills-sort"
                                className={NEO_SELECT_CLASS}
                                value={sortValue}
                                onChange={onSortChange}
                            />
                        </div>
                        {/* @lat: [[bills-category-filter#One control, four themes]] */}
                        <div className="space-y-1.5 md:order-5 md:w-full">
                            <CategoryMultiSelect
                                id="v2-bills-categories"
                                allCategories={allCategories}
                                selectedCategories={selectedCategories}
                                onToggleCategory={onToggleCategory}
                                onClearCategories={onClearCategories}
                                triggerClassName={NEO_SELECT_CLASS}
                                labelClassName={cn(FILTER_EYEBROW, "block")}
                            />
                        </div>
                    </div>
                </div>

                <div className="space-y-4">
                    {/* @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#The bill count is drawn inside the deferred boundary]] */}
                    <Deferred
                        data="bills"
                        fallback={
                            <div className="space-y-4" aria-busy="true" aria-live="polite">
                                <div className="text-sm font-semibold text-muted-foreground">
                                    {PARITY_COPY.bills.loading}
                                </div>
                                <div className="space-y-4" aria-hidden="true">
                                    {[1, 2, 3, 4, 5, 6].map((i) => (
                                        <div key={i} className="placeholder-block h-32 w-full rounded-xl" />
                                    ))}
                                </div>
                            </div>
                        }
                    >
                        <div className="space-y-4">
                            <p className="text-sm text-muted-foreground">
                                {bills.length
                                    ? PARITY_COPY.bills.showingCount(bills.length, formattedSwayLocaleName)
                                    : PARITY_COPY.bills.noneFound(formattedSwayLocaleName)}
                            </p>
                            <div className="space-y-4">
                                {bills.map((bill) => (
                                    <BillCard
                                        key={bill.id}
                                        bill={bill as sway.IBill & { user_vote?: sway.IApiUserVote }}
                                        listMode={listMode}
                                    />
                                ))}
                            </div>
                            {/* @lat: [[bills-category-filter#Why a bill matches on ANY category]] */}
                            {hasMoreBills && (
                                <div className="flex justify-center pt-2">
                                    <Button
                                        type="button"
                                        variant="outline"
                                        disabled={isLoadingMoreBills}
                                        onClick={onLoadMoreBills}
                                        data-testid="btn-load-more-bills"
                                    >
                                        {isLoadingMoreBills ? BILLS_LOADING_MORE_LABEL : BILLS_LOAD_MORE_LABEL}
                                    </Button>
                                </div>
                            )}
                        </div>
                    </Deferred>
                </div>
            </div>
        </div>
    );
};

export default DefaultBillListLayout;
