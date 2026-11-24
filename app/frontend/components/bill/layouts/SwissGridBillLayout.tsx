import { Link, usePage } from "@inertiajs/react";
import { ExternalLink } from "lucide-react";
import type { sway } from "sway";

import BillAsIntroduced from "app/frontend/components/bill/BillAsIntroduced";
import BillSponsorLink from "app/frontend/components/bill/BillSponsorLink";
import LazyBillSummaryMarkdown from "app/frontend/components/bill/layouts/LazyBillSummaryMarkdown";
import EmailLegislatorsModal from "app/frontend/components/bill/EmailLegislatorsModal";
import ShareBillButton from "app/frontend/components/bill/ShareBillButton";
import VotePanel from "app/frontend/components/bill/VotePanel";
import BillAffinityPanel from "app/frontend/components/bill/charts/BillAffinityPanel";
import BillChartsPanel from "app/frontend/components/bill/charts/BillChartsPanel";
import NewsArticleTestimony from "app/frontend/components/bill/NewsArticleTestimony";
import OrgPositionSummary from "app/frontend/components/bill/OrgPositionSummary";
import PublicTestimonySection from "app/frontend/components/bill/PublicTestimonySection";
import RelatedNewsArticles from "app/frontend/components/bill/RelatedNewsArticles";
import {
    isVoteComparisonSuppressed,
    selectBillPositions,
    selectVoteTally,
} from "app/frontend/components/bill/sway_utils/billPositions";
import VoteComparisonPlaceholder from "app/frontend/components/bill/VoteComparisonPlaceholder";
import { hasValidSourceLink } from "app/frontend/components/bill/sway_utils/billSourceLink";
import { hasLegalClause, splitBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";
import { useSwayLocaleSlug } from "app/frontend/hooks/useSwayLocales";
import { formatDate } from "app/frontend/sway_utils/datetimes";
import { titleize } from "app/frontend/sway_utils";
import { ROUTES, VOTING_WEBSITES_BY_SWAY_LOCALE } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import "app/frontend/components/bill/layouts/swiss-grid-bill-layout.css";
import type { BillLayoutProps } from "app/frontend/components/bill/layouts/types";

// @lat: [[theme-driven-bill-layout-selection#Monochrome, Service Manual, and Swiss Notice bill detail layouts]]
const SwissGridBillLayout: React.FC<BillLayoutProps> = ({
    bill,
    sponsor,
    organizations,
    user_vote,
    bill_score,
    isAwaitingScoreUpdate,
}) => {
    const { user, sway_locale, public_testimony_counts, public_testimony_letters } = usePage<sway.IPageProps>().props;
    const swayLocaleSlug = useSwayLocaleSlug();
    const { supporting, opposing } = selectBillPositions(organizations, bill.id);
    const { forCount, againstCount } = selectVoteTally(bill_score);
    const comparisonSuppressed = isVoteComparisonSuppressed(bill_score);
    const { headline, deck } = splitBillTitle(bill.title);

    const status = bill.vote_date_time_utc ? `Voted ${formatDate(bill.vote_date_time_utc)}` : "Awaiting final vote";

    return (
        <div className="sgb-stage">
            <div className="sgb-grid">
                <header className="sgb-row">
                    <div className="sgb-index">{bill.external_id}</div>
                    <div className="sgb-content">
                        <div className="sgb-code">{bill.chamber ? titleize(bill.chamber) : "Legislation"}</div>
                        <h1 className="sgb-headline" data-testid="bill-title">
                            {headline}
                        </h1>
                        {deck && <p className="sgb-deck">{deck}</p>}
                        <div className="sgb-meta">
                            <span>Status: {status}</span>
                            {bill.categories?.length ? <span>Categories: {bill.categories.join(", ")}</span> : null}
                            {sponsor && (
                                <span>
                                    Sponsor:{" "}
                                    <BillSponsorLink legislatorId={bill.legislator_id} className="underline">
                                        {sponsor.full_name}
                                    </BillSponsorLink>
                                </span>
                            )}
                        </div>
                    </div>
                </header>

                <section className="sgb-row">
                    <h2 className="sgb-index">{PARITY_COPY.bill.content.takeNextStep}</h2>
                    <div className="sgb-content">
                        <VotePanel bill={bill} user_vote={user_vote} />
                        <div
                            className="mt-4 flex flex-wrap items-center gap-3"
                            data-testid={user_vote ? "legislator-comparison" : undefined}
                        >
                            {user_vote && (
                                <>
                                    <Link
                                        href={ROUTES.legislators}
                                        className="inline-flex cursor-pointer border border-border-strong bg-surface-1 px-3 py-2 text-xs font-bold uppercase tracking-wider text-foreground transition hover:bg-accent hover:text-accent-foreground"
                                    >
                                        {PARITY_COPY.bill.compareWithReps}
                                    </Link>
                                    <Link
                                        href={ROUTES.pastBills}
                                        className="inline-flex cursor-pointer border border-border-strong bg-surface-1 px-3 py-2 text-xs font-bold uppercase tracking-wider text-foreground transition hover:bg-accent hover:text-accent-foreground"
                                    >
                                        {PARITY_COPY.bill.voteOnPastLegislation}
                                    </Link>
                                    {bill.active !== false && <EmailLegislatorsModal bill={bill} />}
                                </>
                            )}
                            <ShareBillButton bill={bill} />
                            {hasValidSourceLink(bill.link, sway_locale?.generic_portal_urls) ? (
                                <a
                                    href={bill.link as string}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className="inline-flex items-center gap-1.5 border border-border bg-primary px-3 py-2 text-xs font-bold uppercase tracking-wider text-primary-foreground transition"
                                >
                                    {(swayLocaleSlug &&
                                        (VOTING_WEBSITES_BY_SWAY_LOCALE as Record<string, string>)[swayLocaleSlug]) ||
                                        "Official Source"}
                                    <ExternalLink className="size-3.5" aria-hidden="true" />
                                </a>
                            ) : (
                                <p
                                    data-testid="no-source-link"
                                    className="flex items-center text-xs font-semibold text-muted-foreground"
                                >
                                    {PARITY_COPY.bill.officialSourceUnavailable}
                                </p>
                            )}
                        </div>
                    </div>
                </section>

                <section className="sgb-row">
                    <h2 className="sgb-index">{PARITY_COPY.bill.content.swaysSummary}</h2>
                    <div className="sgb-content sgb-prose">
                        <LazyBillSummaryMarkdown
                            summary={bill.summary}
                            aiUnreviewed={bill.summary_ai_unreviewed}
                            billId={bill.id}
                            billLink={bill.link}
                        />
                    </div>
                </section>

                <section className="sgb-row">
                    <h2 className="sgb-index">{PARITY_COPY.bill.content.voteBreakdown}</h2>
                    <div className="sgb-content">
                        <div data-testid="score-panel">
                            {comparisonSuppressed ? (
                                <VoteComparisonPlaceholder votersNeeded={bill_score?.voters_needed} />
                            ) : (
                                <div className="sgb-tally">
                                    <div className="sgb-tally__cell">
                                        <div className="sgb-tally__num">{forCount.toLocaleString()}</div>
                                        <div className="sgb-tally__label">{PARITY_COPY.votePanel.forLabel}</div>
                                    </div>
                                    <div className="sgb-tally__cell">
                                        <div className="sgb-tally__num">{againstCount.toLocaleString()}</div>
                                        <div className="sgb-tally__label">{PARITY_COPY.votePanel.againstLabel}</div>
                                    </div>
                                </div>
                            )}
                        </div>
                        <BillChartsPanel
                            bill={bill}
                            bill_score={bill_score}
                            isAwaitingScoreUpdate={isAwaitingScoreUpdate}
                        />
                        <BillAffinityPanel bill_score={bill_score} />
                    </div>
                </section>

                <section className="sgb-row">
                    <h2 className="sgb-index">{PARITY_COPY.bill.content.whySupport}</h2>
                    <div className="sgb-content">
                        {supporting.length ? (
                            <ul className="sgb-orgs">
                                {supporting.map(({ org, position }) => (
                                    <li key={org.id} className="sgb-org">
                                        <div className="sgb-org__stance">In support</div>
                                        <h3 className="sgb-org__name">{org.name}</h3>
                                        <OrgPositionSummary
                                            summary={position.summary}
                                            summaryAiUnreviewed={position.summary_ai_unreviewed}
                                            className="sgb-org__summary"
                                        />
                                    </li>
                                ))}
                            </ul>
                        ) : (
                            <p className="sgb-empty">{PARITY_COPY.org.noSupport}</p>
                        )}
                        <NewsArticleTestimony
                            testimonies={bill.news_testimonies}
                            stance="support"
                            variant="swiss-grid"
                        />
                    </div>
                </section>

                <section className="sgb-row">
                    <h2 className="sgb-index">{PARITY_COPY.bill.content.whyOppose}</h2>
                    <div className="sgb-content">
                        {opposing.length ? (
                            <ul className="sgb-orgs">
                                {opposing.map(({ org, position }) => (
                                    <li key={org.id} className="sgb-org">
                                        <div className="sgb-org__stance">In opposition</div>
                                        <h3 className="sgb-org__name">{org.name}</h3>
                                        <OrgPositionSummary
                                            summary={position.summary}
                                            summaryAiUnreviewed={position.summary_ai_unreviewed}
                                            className="sgb-org__summary"
                                        />
                                    </li>
                                ))}
                            </ul>
                        ) : (
                            <p className="sgb-empty">{PARITY_COPY.org.noOppose}</p>
                        )}
                        <NewsArticleTestimony
                            testimonies={bill.news_testimonies}
                            stance="oppose"
                            variant="swiss-grid"
                        />
                    </div>
                </section>

                <PublicTestimonySection
                    counts={public_testimony_counts}
                    letters={public_testimony_letters}
                    billTitle={bill.title}
                    billId={bill.id}
                    canOverrideStance={Boolean(user?.is_sway_admin)}
                />

                <RelatedNewsArticles articles={bill.related_articles} variant="swiss-grid" />

                {hasLegalClause(bill.title) && (
                    <div className="sgb-row">
                        <div className="sgb-index" aria-hidden="true">
                            As introduced
                        </div>
                        <div className="sgb-content">
                            <BillAsIntroduced title={bill.title} />
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
};

export default SwissGridBillLayout;
