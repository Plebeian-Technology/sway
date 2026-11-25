import { Deferred } from "@inertiajs/react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { isArchivedHistoricalBill } from "app/frontend/components/bill/sway_utils/billArchiving";
import {
    isVoteComparisonSuppressed,
    selectVoteTally,
    suppressedVoteComparisonLine,
} from "app/frontend/components/bill/sway_utils/billPositions";
import { briefSummary } from "app/frontend/components/bill/sway_utils/billTitle";
import { formatCalendarDay } from "app/frontend/sway_utils/datetimes";
import { sway } from "sway";

import "app/frontend/components/bill/list-layouts/banner-list-layout.css";
import BillEditLink from "app/frontend/components/bill/BillEditLink";
import BillEntryTitle from "app/frontend/components/bill/list-layouts/BillEntryTitle";
import BillRowLink from "app/frontend/components/bill/BillRowLink";
import SwayLocalePicker from "app/frontend/components/locales/SwayLocalePicker";
import BillsSearchInput from "app/frontend/components/bill/list-layouts/BillsSearchInput";
import BillsSessionSelect from "app/frontend/components/bill/list-layouts/BillsSessionSelect";
import BillsSortSelect from "app/frontend/components/bill/list-layouts/BillsSortSelect";
import CategoryMultiSelect from "app/frontend/components/bill/list-layouts/CategoryMultiSelect";
import {
    BILLS_LOAD_MORE_LABEL,
    BILLS_LOADING_MORE_LABEL,
    BILLS_SEARCH_LABEL,
    BILLS_SESSION_LABEL,
    BILLS_SORT_LABEL,
    type BillListLayoutProps,
} from "app/frontend/components/bill/list-layouts/types";

const BannerBillListLayout: React.FC<BillListLayoutProps> = ({
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
    <div className="bnl-stage">
        <div className="bnl-topbar">
            <span className="bnl-wordmark">Sway</span>
            <span className="bnl-edition">Banner edition</span>
        </div>

        <main className="bnl-main">
            <div className="bnl-crumb">
                <span className="bnl-kicker">{formattedSwayLocaleName}</span>
                <span className="bnl-sep">/</span>
                <span className="bnl-cat">The Legislative Record</span>
            </div>

            <h1 className="bnl-title">
                {listMode === "past_bills_of_the_month"
                    ? `${PARITY_COPY.bills.pastBillsOfTheMonthTitle} — ${formattedSwayLocaleName}`
                    : `Bills before ${formattedSwayLocaleName}`}
            </h1>

            <div className="bnl-controls">
                <div className="bnl-field">
                    <label htmlFor="bnl-locale" className="bnl-field__label">
                        Locale
                    </label>
                    <SwayLocalePicker
                        id="bnl-locale"
                        options={localeOptions}
                        value={selectedSwayLocaleId}
                        onChange={onLocaleChange}
                    />
                </div>
                {listMode !== "past_bills_of_the_month" && legislativeSessions.length > 0 && (
                    <div className="bnl-field">
                        <label htmlFor="bnl-session" className="bnl-field__label">
                            {BILLS_SESSION_LABEL}
                        </label>
                        <BillsSessionSelect
                            id="bnl-session"
                            className="bnl-select"
                            sessions={legislativeSessions}
                            value={selectedLegislativeSessionId}
                            onChange={onLegislativeSessionChange}
                        />
                    </div>
                )}
                <div className="bnl-field">
                    <label htmlFor="bnl-sort" className="bnl-field__label">
                        {BILLS_SORT_LABEL}
                    </label>
                    <BillsSortSelect id="bnl-sort" className="bnl-select" value={sortValue} onChange={onSortChange} />
                </div>
                <div className="bnl-field">
                    <label htmlFor="bnl-search" className="bnl-field__label">
                        {BILLS_SEARCH_LABEL}
                    </label>
                    <BillsSearchInput
                        id="bnl-search"
                        className="bnl-select"
                        value={searchValue}
                        onChange={onSearchChange}
                    />
                </div>
                {/* @lat: [[bills-category-filter#One control, four themes]] */}
                <div className="bnl-field bnl-field--wide">
                    <CategoryMultiSelect
                        id="bnl-categories"
                        allCategories={allCategories}
                        selectedCategories={selectedCategories}
                        onToggleCategory={onToggleCategory}
                        onClearCategories={onClearCategories}
                        triggerClassName="bnl-select"
                        labelClassName="bnl-field__label"
                    />
                </div>
            </div>

            {/* @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#The bill count is drawn inside the deferred boundary]] */}
            <Deferred
                data="bills"
                fallback={
                    <div aria-busy="true" aria-live="polite">
                        <p className="bnl-empty">{PARITY_COPY.bills.loading}</p>
                        <ol className="bnl-grid" aria-hidden="true">
                            {[1, 2, 3, 4, 5, 6].map((i) => (
                                <li key={i} className="bnl-card">
                                    <div className="placeholder-block h-28 w-full" />
                                </li>
                            ))}
                        </ol>
                    </div>
                }
            >
                <p className="bnl-count">
                    {bills.length
                        ? PARITY_COPY.bills.showingCount(bills.length, formattedSwayLocaleName)
                        : PARITY_COPY.bills.noneFound(formattedSwayLocaleName)}
                </p>

                <ol className="bnl-grid">
                    {bills.map((bill) => {
                        const entry = bill as sway.IBill & { user_vote?: sway.IApiUserVote };
                        const summary = briefSummary(entry.summary, 180);
                        const { forPercent, againstPercent } = selectVoteTally(entry.bill_score);
                        const releaseDate =
                            listMode === "past_bills_of_the_month"
                                ? formatCalendarDay(entry.scheduled_release_date_utc)
                                : null;
                        return (
                            <li key={entry.id} className="bnl-card">
                                <div className="bnl-card__head">
                                    {entry.categories?.length ? (
                                        <span className="bnl-kicker">{entry.categories.join(" · ")}</span>
                                    ) : null}
                                    <span className="bnl-billno">
                                        Bill {entry.external_id}
                                        {releaseDate && (
                                            <>
                                                {" · "}
                                                <time dateTime={entry.scheduled_release_date_utc}>
                                                    Featured {releaseDate}
                                                </time>
                                            </>
                                        )}
                                    </span>
                                </div>
                                <BillRowLink billId={entry.id} className="bnl-headline">
                                    <BillEntryTitle title={entry.title} qualifierClassName="bnl-qualifier" />
                                </BillRowLink>
                                {summary && <p className="bnl-brief">{summary}</p>}
                                <div className="bnl-cardfoot">
                                    {!isVoteComparisonSuppressed(entry.bill_score) && (
                                        <span className="bnl-bar" aria-hidden="true">
                                            <span style={{ width: `${forPercent}%` }} />
                                        </span>
                                    )}
                                    <span className="bnl-tally">
                                        {isVoteComparisonSuppressed(entry.bill_score)
                                            ? suppressedVoteComparisonLine()
                                            : `${forPercent}% for · ${againstPercent}% against`}
                                    </span>
                                    {entry.user_vote?.support && <span className="bnl-voted">Voted</span>}
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
                    <p className="bnl-count">
                        <button
                            type="button"
                            className="bnl-more"
                            disabled={isLoadingMoreBills}
                            onClick={onLoadMoreBills}
                            data-testid="btn-load-more-bills"
                        >
                            {isLoadingMoreBills ? BILLS_LOADING_MORE_LABEL : BILLS_LOAD_MORE_LABEL}
                        </button>
                    </p>
                )}
            </Deferred>
        </main>
    </div>
);

export default BannerBillListLayout;
