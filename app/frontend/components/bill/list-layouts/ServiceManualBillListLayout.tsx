import { Deferred } from "@inertiajs/react";
import React from "react";
import { sway } from "sway";

import BillEditLink from "app/frontend/components/bill/BillEditLink";
import BillEntryTitle from "app/frontend/components/bill/list-layouts/BillEntryTitle";
import BillRowLink from "app/frontend/components/bill/BillRowLink";
import BillsSearchInput from "app/frontend/components/bill/list-layouts/BillsSearchInput";
import BillsSessionSelect from "app/frontend/components/bill/list-layouts/BillsSessionSelect";
import BillsSortSelect from "app/frontend/components/bill/list-layouts/BillsSortSelect";
import CategoryMultiSelect from "app/frontend/components/bill/list-layouts/CategoryMultiSelect";
import SwayLocalePicker from "app/frontend/components/locales/SwayLocalePicker";
import { isArchivedHistoricalBill } from "app/frontend/components/bill/sway_utils/billArchiving";
import {
    isVoteComparisonSuppressed,
    selectVoteTally,
    suppressedVoteComparisonLine,
} from "app/frontend/components/bill/sway_utils/billPositions";
import { briefSummary } from "app/frontend/components/bill/sway_utils/billTitle";
import { formatCalendarDay, formatDate } from "app/frontend/sway_utils/datetimes";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import "app/frontend/components/bill/list-layouts/service-manual-list-layout.css";
import {
    BILLS_LOAD_MORE_LABEL,
    BILLS_LOADING_MORE_LABEL,
    BILLS_SEARCH_LABEL,
    BILLS_SESSION_LABEL,
    BILLS_SORT_LABEL,
    type BillListLayoutProps,
} from "app/frontend/components/bill/list-layouts/types";

// @lat: [[bill-list-layouts-design#ServiceManualBillListLayout.tsx]]
const ServiceManualBillListLayout: React.FC<BillListLayoutProps> = ({
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
}) => (
    <div className="sml-stage">
        <header className="sml-header">
            <div className="sml-phase-banner">
                <span className="sml-tag">Official Directory</span>
                <span>{formattedSwayLocaleName}</span>
            </div>
            <h1 className="sml-title">
                {listMode === "past_bills_of_the_month"
                    ? PARITY_COPY.bills.pastBillsOfTheMonthTitle
                    : PARITY_COPY.bills.allBillsTitle}
            </h1>
        </header>

        <section className="sml-filter-well">
            <div className="sml-field">
                <label htmlFor="v2-bills-locale" className="sml-field__label">
                    Jurisdiction
                </label>
                <SwayLocalePicker
                    id="v2-bills-locale"
                    options={localeOptions}
                    value={selectedSwayLocaleId}
                    onChange={onLocaleChange}
                />
            </div>

            {listMode !== "past_bills_of_the_month" && legislativeSessions.length > 0 && (
                <div className="sml-field">
                    <label htmlFor="sml-session" className="sml-field__label">
                        {BILLS_SESSION_LABEL}
                    </label>
                    <BillsSessionSelect
                        id="sml-session"
                        className="service-manual-select"
                        sessions={legislativeSessions}
                        value={selectedLegislativeSessionId}
                        onChange={onLegislativeSessionChange}
                    />
                </div>
            )}

            <div className="sml-field">
                <label htmlFor="sml-sort" className="sml-field__label">
                    {BILLS_SORT_LABEL}
                </label>
                <BillsSortSelect
                    id="sml-sort"
                    className="service-manual-select"
                    value={sortValue}
                    onChange={onSortChange}
                />
            </div>

            <div className="sml-field">
                <label htmlFor="sml-search" className="sml-field__label">
                    {BILLS_SEARCH_LABEL}
                </label>
                <BillsSearchInput
                    id="sml-search"
                    className="service-manual-select sml-input"
                    value={searchValue}
                    onChange={onSearchChange}
                />
            </div>

            <div className="sml-field sml-field--wide">
                <CategoryMultiSelect
                    id="sml-categories"
                    allCategories={allCategories}
                    selectedCategories={selectedCategories}
                    onToggleCategory={onToggleCategory}
                    onClearCategories={onClearCategories}
                    triggerClassName="service-manual-select"
                    labelClassName="sml-field__label"
                />
            </div>
        </section>

        <Deferred
            data="bills"
            fallback={
                <div aria-busy="true" aria-live="polite">
                    <p className="sml-count">{PARITY_COPY.bills.loading}</p>
                    <ol className="sml-entries" aria-hidden="true">
                        {[1, 2, 3, 4, 5, 6].map((i) => (
                            <li key={i} className="sml-entry">
                                <div className="placeholder-block h-24 w-full" />
                            </li>
                        ))}
                    </ol>
                </div>
            }
        >
            <p className="sml-count">
                {bills.length
                    ? PARITY_COPY.bills.showingCount(bills.length, formattedSwayLocaleName)
                    : PARITY_COPY.bills.noneFound(formattedSwayLocaleName)}
            </p>

            <ol className="sml-entries">
                {bills.map((bill) => {
                    const entry = bill as sway.IBill & { user_vote?: sway.IApiUserVote };
                    const summary = briefSummary(entry.summary, 180);
                    const { forCount, againstCount } = selectVoteTally(entry.bill_score);
                    const introDate = entry.introduced_date_time_utc
                        ? formatDate(entry.introduced_date_time_utc)
                        : null;
                    const releaseDate =
                        listMode === "past_bills_of_the_month"
                            ? formatCalendarDay(entry.scheduled_release_date_utc)
                            : null;
                    return (
                        <li key={entry.id} className="sml-entry">
                            <div className="sml-entry__meta">
                                <span className="sml-code">{entry.external_id}</span>
                                {entry.chamber && <span className="sml-tag sml-tag--neutral">{entry.chamber}</span>}
                                {releaseDate && (
                                    <time dateTime={entry.scheduled_release_date_utc}>Featured {releaseDate}</time>
                                )}
                                {introDate && <span>Introduced {introDate}</span>}
                            </div>

                            <BillRowLink billId={entry.id} className="sml-entry__title">
                                <BillEntryTitle title={entry.title} qualifierClassName="sml-entry__qualifier" />
                            </BillRowLink>
                            {summary && <p className="sml-entry__brief">{summary}</p>}

                            <div className="sml-entry__foot">
                                <span className="sml-tally">
                                    {isVoteComparisonSuppressed(entry.bill_score)
                                        ? suppressedVoteComparisonLine(entry.bill_score)
                                        : `${forCount.toLocaleString()} for · ${againstCount.toLocaleString()} against`}
                                </span>
                                {entry.user_vote?.support && <span className="sml-voted">Vote recorded</span>}
                                <BillEditLink
                                    billId={entry.id}
                                    billIdentifier={entry.external_id}
                                    isArchived={isArchivedHistoricalBill(entry)}
                                />
                            </div>
                        </li>
                    );
                })}
            </ol>

            {hasMoreBills && (
                <p className="sml-count">
                    <button
                        type="button"
                        className="sml-more"
                        disabled={isLoadingMoreBills}
                        onClick={onLoadMoreBills}
                        data-testid="btn-load-more-bills"
                    >
                        {isLoadingMoreBills ? BILLS_LOADING_MORE_LABEL : BILLS_LOAD_MORE_LABEL}
                    </button>
                </p>
            )}
        </Deferred>
    </div>
);

export default ServiceManualBillListLayout;
