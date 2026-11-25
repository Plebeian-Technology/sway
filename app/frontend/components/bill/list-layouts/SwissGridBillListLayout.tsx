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

import "app/frontend/components/bill/list-layouts/swiss-grid-list-layout.css";
import {
    BILLS_LOAD_MORE_LABEL,
    BILLS_LOADING_MORE_LABEL,
    BILLS_SEARCH_LABEL,
    BILLS_SESSION_LABEL,
    BILLS_SORT_LABEL,
    type BillListLayoutProps,
} from "app/frontend/components/bill/list-layouts/types";

// @lat: [[bill-list-layouts-design#SwissGridBillListLayout.tsx]]
const SwissGridBillListLayout: React.FC<BillListLayoutProps> = ({
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
    <div className="sgl-stage">
        <div className="sgl-grid">
            <header className="sgl-row">
                <div className="sgl-index">01 / JURISDICTION</div>
                <div className="sgl-content">
                    <h1 className="sgl-headline">{formattedSwayLocaleName}</h1>
                    <p className="sgl-subhead">
                        {listMode === "past_bills_of_the_month"
                            ? PARITY_COPY.bills.pastBillsOfTheMonthTitle
                            : PARITY_COPY.bills.allBillsTitle}
                    </p>
                </div>
            </header>

            <section className="sgl-row">
                <div className="sgl-index">02 / CONTROLS</div>
                <div className="sgl-content sgl-controls">
                    <div className="sgl-field">
                        <label htmlFor="v2-bills-locale" className="sgl-field__label">
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
                        <div className="sgl-field">
                            <label htmlFor="sgl-session" className="sgl-field__label">
                                {BILLS_SESSION_LABEL}
                            </label>
                            <BillsSessionSelect
                                id="sgl-session"
                                className="swiss-grid-select"
                                sessions={legislativeSessions}
                                value={selectedLegislativeSessionId}
                                onChange={onLegislativeSessionChange}
                            />
                        </div>
                    )}

                    <div className="sgl-field">
                        <label htmlFor="sgl-sort" className="sgl-field__label">
                            {BILLS_SORT_LABEL}
                        </label>
                        <BillsSortSelect
                            id="sgl-sort"
                            className="swiss-grid-select"
                            value={sortValue}
                            onChange={onSortChange}
                        />
                    </div>

                    <div className="sgl-field">
                        <label htmlFor="sgl-search" className="sgl-field__label">
                            {BILLS_SEARCH_LABEL}
                        </label>
                        <BillsSearchInput
                            id="sgl-search"
                            className="swiss-grid-select sgl-input"
                            value={searchValue}
                            onChange={onSearchChange}
                        />
                    </div>

                    <div className="sgl-field sgl-field--wide">
                        <CategoryMultiSelect
                            id="sgl-categories"
                            allCategories={allCategories}
                            selectedCategories={selectedCategories}
                            onToggleCategory={onToggleCategory}
                            onClearCategories={onClearCategories}
                            triggerClassName="swiss-grid-select"
                            labelClassName="sgl-field__label"
                        />
                    </div>
                </div>
            </section>

            <Deferred
                data="bills"
                fallback={
                    <div aria-busy="true" aria-live="polite">
                        <div className="sgl-row">
                            <div className="sgl-index">STATUS</div>
                            <div className="sgl-content">
                                <p className="sgl-count">{PARITY_COPY.bills.loading}</p>
                                <ol className="sgl-placeholders" aria-hidden="true">
                                    {[1, 2, 3, 4, 5, 6].map((i) => (
                                        <li key={i}>
                                            <div className="placeholder-block h-20 w-full" />
                                        </li>
                                    ))}
                                </ol>
                            </div>
                        </div>
                    </div>
                }
            >
                <div>
                    <p className="sgl-count sgl-count-row">
                        {bills.length
                            ? PARITY_COPY.bills.showingCount(bills.length, formattedSwayLocaleName)
                            : PARITY_COPY.bills.noneFound(formattedSwayLocaleName)}
                    </p>

                    <ol className="sgl-ledger">
                        {bills.map((bill) => {
                            const entry = bill as sway.IBill & { user_vote?: sway.IApiUserVote };
                            const summary = briefSummary(entry.summary, 180);
                            const { forPercent, againstPercent } = selectVoteTally(entry.bill_score);
                            const introDate = entry.introduced_date_time_utc
                                ? formatDate(entry.introduced_date_time_utc)
                                : null;
                            const releaseDate =
                                listMode === "past_bills_of_the_month"
                                    ? formatCalendarDay(entry.scheduled_release_date_utc)
                                    : null;
                            return (
                                <li key={entry.id} className="sgl-row">
                                    <div className="sgl-index">
                                        <span className="sgl-code">{entry.external_id}</span>
                                        {entry.chamber && <span className="sgl-chamber">{entry.chamber}</span>}
                                    </div>

                                    <div className="sgl-content">
                                        <BillRowLink billId={entry.id} className="sgl-row__title">
                                            <BillEntryTitle title={entry.title} qualifierClassName="sgl-qualifier" />
                                        </BillRowLink>
                                        {summary && <p className="sgl-brief">{summary}</p>}

                                        <div className="sgl-foot">
                                            <span className="sgl-tally">
                                                {isVoteComparisonSuppressed(entry.bill_score)
                                                    ? suppressedVoteComparisonLine()
                                                    : `${forPercent}% for · ${againstPercent}% against`}
                                            </span>
                                            {releaseDate && (
                                                <time dateTime={entry.scheduled_release_date_utc} className="sgl-date">
                                                    Featured {releaseDate}
                                                </time>
                                            )}
                                            {introDate && <span className="sgl-date">Introduced {introDate}</span>}
                                            {entry.user_vote?.support && (
                                                <span className="sgl-voted">Vote recorded</span>
                                            )}
                                            <BillEditLink
                                                billId={entry.id}
                                                billIdentifier={entry.external_id}
                                                isArchived={isArchivedHistoricalBill(entry)}
                                            />
                                        </div>
                                    </div>
                                </li>
                            );
                        })}
                    </ol>

                    {hasMoreBills && (
                        <div className="sgl-row">
                            <div className="sgl-index">NAVIGATE</div>
                            <div className="sgl-content">
                                <button
                                    type="button"
                                    className="sgl-more"
                                    disabled={isLoadingMoreBills}
                                    onClick={onLoadMoreBills}
                                    data-testid="btn-load-more-bills"
                                >
                                    {isLoadingMoreBills ? BILLS_LOADING_MORE_LABEL : BILLS_LOAD_MORE_LABEL}
                                </button>
                            </div>
                        </div>
                    )}
                </div>
            </Deferred>
        </div>
    </div>
);

export default SwissGridBillListLayout;
