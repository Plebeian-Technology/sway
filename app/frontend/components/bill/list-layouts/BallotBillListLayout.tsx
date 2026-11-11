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
import { selectVoteTally } from "app/frontend/components/bill/sway_utils/billPositions";
import { briefSummary } from "app/frontend/components/bill/sway_utils/billTitle";
import { formatCalendarDay } from "app/frontend/sway_utils/datetimes";
import { sway } from "sway";

import "app/frontend/components/bill/list-layouts/ballot-list-layout.css";
import {
    BILLS_LOAD_MORE_LABEL,
    BILLS_LOADING_MORE_LABEL,
    BILLS_SEARCH_LABEL,
    BILLS_SESSION_LABEL,
    BILLS_SORT_LABEL,
    type BillListLayoutProps,
} from "app/frontend/components/bill/list-layouts/types";

// @lat: [[bill-list-layout-props-contract#BillListLayoutProps contract]]
const BallotBillListLayout: React.FC<BillListLayoutProps> = ({
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
    <div className="ball-sheet">
        <header className="ball-header">
            <div className="ball-header__locale">
                {localeSlug && <SwayLocaleFlag swayLocaleSlug={localeSlug} className="ball-header__flag" />}
                <div>
                    <p className="ball-header__kind">
                        {listMode === "past_bills_of_the_month"
                            ? PARITY_COPY.bills.pastBillsOfTheMonthTitle
                            : "Official ballot"}
                    </p>
                    <h1 className="ball-header__title">{formattedSwayLocaleName}</h1>
                </div>
            </div>
        </header>

        <section className="ball-controls">
            <div className="ball-field">
                <label htmlFor="ball-locale" className="ball-field__label">
                    Jurisdiction
                </label>
                <SwayLocalePicker
                    id="ball-locale"
                    options={localeOptions}
                    value={selectedSwayLocaleId}
                    onChange={onLocaleChange}
                />
            </div>

            {listMode !== "past_bills_of_the_month" && legislativeSessions.length > 0 && (
                <div className="ball-field">
                    <label htmlFor="ball-session" className="ball-field__label">
                        {BILLS_SESSION_LABEL}
                    </label>
                    <BillsSessionSelect
                        id="ball-session"
                        className="ball-select"
                        sessions={legislativeSessions}
                        value={selectedLegislativeSessionId}
                        onChange={onLegislativeSessionChange}
                    />
                </div>
            )}

            <div className="ball-field">
                <label htmlFor="ball-sort" className="ball-field__label">
                    {BILLS_SORT_LABEL}
                </label>
                <BillsSortSelect id="ball-sort" className="ball-select" value={sortValue} onChange={onSortChange} />
            </div>

            <div className="ball-field">
                <label htmlFor="ball-search" className="ball-field__label">
                    {BILLS_SEARCH_LABEL}
                </label>
                <BillsSearchInput
                    id="ball-search"
                    className="ball-select ball-input"
                    value={searchValue}
                    onChange={onSearchChange}
                />
            </div>

            {/* @lat: [[bills-category-filter#One control, four themes]] */}
            <div className="ball-field ball-field--wide">
                <CategoryMultiSelect
                    id="ball-categories"
                    allCategories={allCategories}
                    selectedCategories={selectedCategories}
                    onToggleCategory={onToggleCategory}
                    onClearCategories={onClearCategories}
                    triggerClassName="ball-select"
                    labelClassName="ball-field__label"
                />
            </div>
        </section>

        {/* @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#The bill count is drawn inside the deferred boundary]] */}
        <Deferred
            data="bills"
            fallback={
                <div aria-busy="true" aria-live="polite">
                    <p className="ball-count">{PARITY_COPY.bills.loading}</p>
                    <ol className="ball-contests" aria-hidden="true">
                        {[1, 2, 3, 4, 5, 6].map((i) => (
                            <li key={i} className="ball-contest">
                                <div className="placeholder-block h-24 w-full" />
                            </li>
                        ))}
                    </ol>
                </div>
            }
        >
            <p className="ball-count">
                {bills.length
                    ? PARITY_COPY.bills.showingCount(bills.length, formattedSwayLocaleName)
                    : PARITY_COPY.bills.noneFound(formattedSwayLocaleName)}
            </p>

            <ol className="ball-contests">
                {bills.map((bill) => {
                    const entry = bill as sway.IBill & { user_vote?: sway.IApiUserVote };
                    const summary = briefSummary(entry.summary, 200);
                    const { forCount, againstCount } = selectVoteTally(entry.bill_score);
                    const releaseDate =
                        listMode === "past_bills_of_the_month"
                            ? formatCalendarDay(entry.scheduled_release_date_utc)
                            : null;
                    return (
                        <li key={entry.id} className="ball-contest">
                            <div className="ball-contest__id">
                                <span className="ball-code">{entry.external_id}</span>
                                {entry.chamber && <span className="ball-kind">{entry.chamber} bill</span>}
                                {releaseDate && (
                                    <time dateTime={entry.scheduled_release_date_utc} className="ball-kind">
                                        Featured {releaseDate}
                                    </time>
                                )}
                            </div>

                            <BillRowLink billId={entry.id} className="ball-contest__title">
                                <BillEntryTitle title={entry.title} qualifierClassName="ball-contest__qualifier" />
                            </BillRowLink>
                            {summary && <p className="ball-contest__brief">{summary}</p>}

                            <div className="ball-contest__foot">
                                <span className="ball-tally">
                                    {forCount.toLocaleString()} for · {againstCount.toLocaleString()} against
                                </span>
                                {entry.user_vote?.support && <span className="ball-voted">Vote recorded</span>}
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
                <p className="ball-count">
                    <button
                        type="button"
                        className="ball-more"
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

export default BallotBillListLayout;
