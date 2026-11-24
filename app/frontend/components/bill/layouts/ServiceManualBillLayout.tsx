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
import { splitBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";
import { useSwayLocaleSlug } from "app/frontend/hooks/useSwayLocales";
import { formatDate } from "app/frontend/sway_utils/datetimes";
import { titleize } from "app/frontend/sway_utils";
import { ROUTES, VOTING_WEBSITES_BY_SWAY_LOCALE } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import "app/frontend/components/bill/layouts/service-manual-bill-layout.css";
import type { BillLayoutProps } from "app/frontend/components/bill/layouts/types";

// @lat: [[theme-driven-bill-layout-selection#Monochrome, Service Manual, and Swiss Notice bill detail layouts]]
const ServiceManualBillLayout: React.FC<BillLayoutProps> = ({
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
        <div className="smb-stage">
            <header className="smb-header">
                <div className="smb-phase-banner">
                    <span className="smb-tag">Legislation</span>
                    <span>{bill.external_id}</span>
                    {bill.chamber && <span>· {titleize(bill.chamber)}</span>}
                </div>
                <h1 className="smb-shorttitle" data-testid="bill-title">
                    {headline}
                </h1>
                {deck && <p className="smb-deck">{deck}</p>}
            </header>

            <div className="smb-split">
                <div className="smb-main">
                    <div className="smb-callout">
                        <h2 className="smb-callout__title">{PARITY_COPY.bill.content.swaysSummary}</h2>
                        <LazyBillSummaryMarkdown
                            summary={bill.summary}
                            aiUnreviewed={bill.summary_ai_unreviewed}
                            billId={bill.id}
                            billLink={bill.link}
                        />
                    </div>

                    <RelatedNewsArticles articles={bill.related_articles} variant="service-manual" />

                    <section className="smb-section">
                        <h2 className="smb-sectionlabel">{PARITY_COPY.bill.content.whySupport}</h2>
                        {supporting.length ? (
                            <ul className="smb-orgs">
                                {supporting.map(({ org, position }) => (
                                    <li key={org.id} className="smb-org">
                                        <span className="smb-org__stance smb-org__stance--for">In support</span>
                                        <h3 className="smb-org__name">{org.name}</h3>
                                        <OrgPositionSummary
                                            summary={position.summary}
                                            summaryAiUnreviewed={position.summary_ai_unreviewed}
                                            className="smb-org__summary"
                                        />
                                    </li>
                                ))}
                            </ul>
                        ) : (
                            <p className="smb-empty">{PARITY_COPY.org.noSupport}</p>
                        )}
                        <NewsArticleTestimony
                            testimonies={bill.news_testimonies}
                            stance="support"
                            variant="service-manual"
                        />
                    </section>

                    <section className="smb-section">
                        <h2 className="smb-sectionlabel">{PARITY_COPY.bill.content.whyOppose}</h2>
                        {opposing.length ? (
                            <ul className="smb-orgs">
                                {opposing.map(({ org, position }) => (
                                    <li key={org.id} className="smb-org">
                                        <span className="smb-org__stance smb-org__stance--against">In opposition</span>
                                        <h3 className="smb-org__name">{org.name}</h3>
                                        <OrgPositionSummary
                                            summary={position.summary}
                                            summaryAiUnreviewed={position.summary_ai_unreviewed}
                                            className="smb-org__summary"
                                        />
                                    </li>
                                ))}
                            </ul>
                        ) : (
                            <p className="smb-empty">{PARITY_COPY.org.noOppose}</p>
                        )}
                        <NewsArticleTestimony
                            testimonies={bill.news_testimonies}
                            stance="oppose"
                            variant="service-manual"
                        />
                    </section>

                    <PublicTestimonySection
                        counts={public_testimony_counts}
                        letters={public_testimony_letters}
                        billTitle={bill.title}
                        billId={bill.id}
                        canOverrideStance={Boolean(user?.is_sway_admin)}
                    />

                    <BillAsIntroduced title={bill.title} />
                </div>

                <aside className="smb-rail">
                    <div className="smb-meta-card">
                        <VotePanel bill={bill} user_vote={user_vote} />
                        <div data-testid="score-panel">
                            {comparisonSuppressed ? (
                                <VoteComparisonPlaceholder votersNeeded={bill_score?.voters_needed} />
                            ) : (
                                <div className="smb-tally">
                                    <div className="smb-tally__cell">
                                        <div className="smb-tally__num">{forCount.toLocaleString()}</div>
                                        <div className="smb-tally__label">{PARITY_COPY.votePanel.forLabel}</div>
                                    </div>
                                    <div className="smb-tally__cell">
                                        <div className="smb-tally__num">{againstCount.toLocaleString()}</div>
                                        <div className="smb-tally__label">{PARITY_COPY.votePanel.againstLabel}</div>
                                    </div>
                                </div>
                            )}
                        </div>
                        <div
                            className="mt-4 flex flex-wrap items-center gap-3"
                            data-testid={user_vote ? "legislator-comparison" : undefined}
                        >
                            {user_vote && (
                                <>
                                    <Link
                                        href={ROUTES.legislators}
                                        className="inline-flex cursor-pointer border border-border-strong bg-surface-2 px-3 py-2 text-xs font-bold text-foreground transition hover:bg-accent hover:text-accent-foreground"
                                    >
                                        {PARITY_COPY.bill.compareWithReps}
                                    </Link>
                                    <Link
                                        href={ROUTES.pastBills}
                                        className="inline-flex cursor-pointer border border-border-strong bg-surface-2 px-3 py-2 text-xs font-bold text-foreground transition hover:bg-accent hover:text-accent-foreground"
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
                                    className="inline-flex items-center gap-1.5 border border-border bg-primary px-3 py-2 text-xs font-bold text-primary-foreground transition"
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

                    <div className="smb-meta-card">
                        <h2 className="smb-meta-card__title">Metadata</h2>
                        <dl className="smb-meta-list">
                            <div className="smb-meta-item">
                                <dt>Bill reference</dt>
                                <dd>{bill.external_id}</dd>
                            </div>
                            <div className="smb-meta-item">
                                <dt>Status</dt>
                                <dd>{status}</dd>
                            </div>
                            {bill.categories?.length ? (
                                <div className="smb-meta-item">
                                    <dt>Categories</dt>
                                    <dd>{bill.categories.join(", ")}</dd>
                                </div>
                            ) : null}
                            {sponsor && (
                                <div className="smb-meta-item">
                                    <dt>Sponsor</dt>
                                    <dd>
                                        <BillSponsorLink legislatorId={bill.legislator_id} className="underline">
                                            {sponsor.full_name}
                                        </BillSponsorLink>
                                    </dd>
                                </div>
                            )}
                        </dl>
                    </div>

                    <BillChartsPanel
                        bill={bill}
                        bill_score={bill_score}
                        isAwaitingScoreUpdate={isAwaitingScoreUpdate}
                    />
                    <BillAffinityPanel bill_score={bill_score} />
                </aside>
            </div>
        </div>
    );
};

export default ServiceManualBillLayout;
