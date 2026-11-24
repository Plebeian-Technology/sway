import { Deferred } from "@inertiajs/react";

import BillEditLink from "app/frontend/components/bill/BillEditLink";
import BillEntryTitle from "app/frontend/components/bill/list-layouts/BillEntryTitle";
import BillRowLink from "app/frontend/components/bill/BillRowLink";
import SwayLocalePicker from "app/frontend/components/locales/SwayLocalePicker";
import BillsSearchInput from "app/frontend/components/bill/list-layouts/BillsSearchInput";
import BillsSessionSelect from "app/frontend/components/bill/list-layouts/BillsSessionSelect";
import BillsSortSelect from "app/frontend/components/bill/list-layouts/BillsSortSelect";
import CategoryMultiSelect from "app/frontend/components/bill/list-layouts/CategoryMultiSelect";
import SwayLocaleFlag from "app/frontend/components/locales/SwayLocaleFlag";
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

import "app/frontend/components/bill/list-layouts/cornerstore-list-layout.css";
import {
    BILLS_LOAD_MORE_LABEL,
    BILLS_LOADING_MORE_LABEL,
    BILLS_SEARCH_LABEL,
    BILLS_SESSION_LABEL,
    BILLS_SORT_LABEL,
    type BillListLayoutProps,
} from "app/frontend/components/bill/list-layouts/types";

// @lat: [[bill-list-layout-props-contract#BillListLayoutProps contract]]
const CornerstoreBillListLayout: React.FC<BillListLayoutProps> = ({
    bills,
    formattedSwayLocaleName,
    localeSlug,
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
    <div className="csl-stage">
        <div className="csl-masthead">
            {localeSlug && <SwayLocaleFlag swayLocaleSlug={localeSlug} className="csl-masthead__flag" />}
            <div className="csl-kicker">
                {listMode === "past_bills_of_the_month" ? PARITY_COPY.bills.pastBillsOfTheMonthTitle : "On the board"}
            </div>
        </div>

        <h1 className="csl-headline">{formattedSwayLocaleName}</h1>

        <section className="csl-controls">
            <div className="csl-field">
                <label htmlFor="csl-locale" className="csl-field__label">
                    Neighborhood
                </label>
                <SwayLocalePicker
                    id="csl-locale"
                    options={localeOptions}
                    value={selectedSwayLocaleId}
                    onChange={onLocaleChange}
                />
            </div>

            {listMode !== "past_bills_of_the_month" && legislativeSessions.length > 0 && (
                <div className="csl-field">
                    <label htmlFor="csl-session" className="csl-field__label">
                        {BILLS_SESSION_LABEL}
                    </label>
                    <BillsSessionSelect
                        id="csl-session"
                        className="csl-select"
                        sessions={legislativeSessions}
                        value={selectedLegislativeSessionId}
                        onChange={onLegislativeSessionChange}
                    />
                </div>
            )}

            <div className="csl-field">
                <label htmlFor="csl-sort" className="csl-field__label">
                    {BILLS_SORT_LABEL}
                </label>
                <BillsSortSelect id="csl-sort" className="csl-select" value={sortValue} onChange={onSortChange} />
            </div>

            <div className="csl-field">
                <label htmlFor="csl-search" className="csl-field__label">
                    {BILLS_SEARCH_LABEL}
                </label>
                <BillsSearchInput
                    id="csl-search"
                    className="csl-select csl-input"
                    value={searchValue}
                    onChange={onSearchChange}
                />
            </div>

            {/* @lat: [[bills-category-filter#One control, four themes]] */}
            <div className="csl-field csl-field--wide">
                <CategoryMultiSelect
                    id="csl-categories"
                    allCategories={allCategories}
                    selectedCategories={selectedCategories}
                    onToggleCategory={onToggleCategory}
                    onClearCategories={onClearCategories}
                    triggerClassName="csl-select"
                    labelClassName="csl-field__label"
                />
            </div>
        </section>

        {/* @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#The bill count is drawn inside the deferred boundary]] */}
        <Deferred
            data="bills"
            fallback={
                <div aria-busy="true" aria-live="polite">
                    <p className="csl-count">{PARITY_COPY.bills.loading}</p>
                    <ol className="csl-board" aria-hidden="true">
                        {[1, 2, 3, 4, 5, 6].map((i) => (
                            <li key={i} className="csl-poster">
                                <div className="placeholder-block h-32 w-full" />
                            </li>
                        ))}
                    </ol>
                </div>
            }
        >
            <p className="csl-count">
                {bills.length
                    ? PARITY_COPY.bills.showingCount(bills.length, formattedSwayLocaleName)
                    : PARITY_COPY.bills.noneFound(formattedSwayLocaleName)}
            </p>

            <ol className="csl-board">
                {bills.map((bill) => {
                    const entry = bill as sway.IBill & { user_vote?: sway.IApiUserVote };
                    const summary = briefSummary(entry.summary, 160);
                    const { forCount, againstCount } = selectVoteTally(entry.bill_score);
                    const releaseDate =
                        listMode === "past_bills_of_the_month"
                            ? formatCalendarDay(entry.scheduled_release_date_utc)
                            : null;
                    return (
                        <li key={entry.id} className="csl-poster">
                            <div className="csl-poster__code">{entry.external_id}</div>
                            {entry.chamber && <p className="csl-poster__kind">{entry.chamber} bill</p>}
                            {releaseDate && (
                                <p className="csl-poster__kind">
                                    <time dateTime={entry.scheduled_release_date_utc}>Featured {releaseDate}</time>
                                </p>
                            )}

                            <BillRowLink billId={entry.id} className="csl-poster__title">
                                <BillEntryTitle title={entry.title} qualifierClassName="csl-poster__qualifier" />
                            </BillRowLink>
                            {summary && <p className="csl-poster__brief">{summary}</p>}

                            <div className="csl-poster__foot">
                                <span className="csl-tally">
                                    {isVoteComparisonSuppressed(entry.bill_score)
                                        ? suppressedVoteComparisonLine(entry.bill_score)
                                        : `${forCount.toLocaleString()} for · ${againstCount.toLocaleString()} against`}
                                </span>
                                {entry.user_vote?.support && <span className="csl-voted">Vote recorded</span>}
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
                <p className="csl-count">
                    <button
                        type="button"
                        className="csl-more"
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

export default CornerstoreBillListLayout;
