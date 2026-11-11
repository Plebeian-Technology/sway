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
import { selectBillPositions, selectVoteTally } from "app/frontend/components/bill/sway_utils/billPositions";
import { hasValidSourceLink } from "app/frontend/components/bill/sway_utils/billSourceLink";
import { splitBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";
import { useSwayLocaleSlug } from "app/frontend/hooks/useSwayLocales";
import { formatDate } from "app/frontend/sway_utils/datetimes";
import { titleize } from "app/frontend/sway_utils";
import { ROUTES, VOTING_WEBSITES_BY_SWAY_LOCALE } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import "app/frontend/components/bill/layouts/monochrome-bill-layout.css";
import type { BillLayoutProps } from "app/frontend/components/bill/layouts/types";

// @lat: [[theme-driven-bill-layout-selection#Monochrome, Service Manual, and Swiss Notice bill detail layouts]]
const MonochromeBillLayout: React.FC<BillLayoutProps> = ({
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
    const { forCount, againstCount, total, forPct } = selectVoteTally(bill_score);
    const againstPct = total > 0 ? 100 - forPct : 0;
    const { headline, deck } = splitBillTitle(bill.title);

    const dateStr = bill.vote_date_time_utc
        ? `Voted ${formatDate(bill.vote_date_time_utc)}`
        : bill.introduced_date_time_utc
          ? `Introduced ${formatDate(bill.introduced_date_time_utc)}`
          : "Awaiting final vote";

    return (
        <div className="mcb-stage">
            <div className="mcb-meta-strip font-mono">
                <span className="mcb-code">{bill.external_id}</span>
                {bill.chamber && <span>{titleize(bill.chamber)}</span>}
                {bill.categories?.length ? <span>{bill.categories.join(" · ")}</span> : null}
                <span>{dateStr}</span>
                {sponsor && (
                    <BillSponsorLink legislatorId={bill.legislator_id} className="underline">
                        {sponsor.full_name}
                    </BillSponsorLink>
                )}
            </div>

            <header className="mcb-head">
                <h1 className="mcb-shorttitle" data-testid="bill-title">
                    {headline}
                </h1>
                {deck && <p className="mcb-deck">{deck}</p>}
            </header>

            <section className="mcb-vote-section">
                <VotePanel bill={bill} user_vote={user_vote} />
                <div className="mcb-tally" data-testid="score-panel">
                    <div className="mcb-tally__row">
                        <div className="mcb-tally__meta">
                            <span className="mcb-tally__label">
                                {PARITY_COPY.votePanel.forLabel} ({forCount.toLocaleString()})
                            </span>
                            <span className="mcb-tally__pct">{Math.round(forPct)}%</span>
                        </div>
                        <div className="mcb-tally__track">
                            <div className="mcb-tally__bar--for" style={{ width: `${forPct}%` }} />
                        </div>
                    </div>

                    <div className="mcb-tally__row">
                        <div className="mcb-tally__meta">
                            <span className="mcb-tally__label">
                                {PARITY_COPY.votePanel.againstLabel} ({againstCount.toLocaleString()})
                            </span>
                            <span className="mcb-tally__pct">{Math.round(againstPct)}%</span>
                        </div>
                        <div className="mcb-tally__track">
                            <div className="mcb-tally__bar--against" style={{ width: `${againstPct}%` }} />
                        </div>
                    </div>
                </div>

                <div
                    className="mt-4 flex flex-wrap items-center gap-3 font-mono"
                    data-testid={user_vote ? "legislator-comparison" : undefined}
                >
                    {user_vote && (
                        <>
                            <Link
                                href={ROUTES.legislators}
                                className="inline-flex cursor-pointer border border-foreground px-3 py-2 text-xs font-bold uppercase tracking-wider text-foreground transition hover:bg-foreground hover:text-background"
                            >
                                {PARITY_COPY.bill.compareWithReps}
                            </Link>
                            <Link
                                href={ROUTES.pastBills}
                                className="inline-flex cursor-pointer border border-foreground px-3 py-2 text-xs font-bold uppercase tracking-wider text-foreground transition hover:bg-foreground hover:text-background"
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
                            className="inline-flex items-center gap-1.5 border border-foreground bg-foreground px-3 py-2 text-xs font-bold uppercase tracking-wider text-background transition"
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
            </section>

            <BillChartsPanel bill={bill} bill_score={bill_score} isAwaitingScoreUpdate={isAwaitingScoreUpdate} />
            <BillAffinityPanel bill_score={bill_score} />

            <section className="mcb-section">
                <h2 className="mcb-sectionlabel">{PARITY_COPY.bill.content.swaysSummary}</h2>
                <div className="mcb-prose">
                    <LazyBillSummaryMarkdown
                        summary={bill.summary}
                        aiUnreviewed={bill.summary_ai_unreviewed}
                        billId={bill.id}
                        billLink={bill.link}
                    />
                </div>
            </section>

            <RelatedNewsArticles articles={bill.related_articles} variant="monochrome" />

            <section className="mcb-section">
                <h2 className="mcb-sectionlabel">{PARITY_COPY.bill.content.whySupport}</h2>
                {supporting.length ? (
                    <ul className="mcb-orgs">
                        {supporting.map(({ org, position }) => (
                            <li key={org.id} className="mcb-org">
                                <span className="mcb-org__stance font-mono">For</span>
                                <div>
                                    <h3 className="mcb-org__name font-mono">{org.name}</h3>
                                    <OrgPositionSummary
                                        summary={position.summary}
                                        summaryAiUnreviewed={position.summary_ai_unreviewed}
                                        className="mcb-org__summary"
                                    />
                                </div>
                            </li>
                        ))}
                    </ul>
                ) : (
                    <p className="mcb-empty">{PARITY_COPY.org.noSupport}</p>
                )}
                <NewsArticleTestimony testimonies={bill.news_testimonies} stance="support" variant="monochrome" />
            </section>

            <section className="mcb-section">
                <h2 className="mcb-sectionlabel">{PARITY_COPY.bill.content.whyOppose}</h2>
                {opposing.length ? (
                    <ul className="mcb-orgs">
                        {opposing.map(({ org, position }) => (
                            <li key={org.id} className="mcb-org">
                                <span className="mcb-org__stance font-mono">Against</span>
                                <div>
                                    <h3 className="mcb-org__name font-mono">{org.name}</h3>
                                    <OrgPositionSummary
                                        summary={position.summary}
                                        summaryAiUnreviewed={position.summary_ai_unreviewed}
                                        className="mcb-org__summary"
                                    />
                                </div>
                            </li>
                        ))}
                    </ul>
                ) : (
                    <p className="mcb-empty">{PARITY_COPY.org.noOppose}</p>
                )}
                <NewsArticleTestimony testimonies={bill.news_testimonies} stance="oppose" variant="monochrome" />
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
    );
};

export default MonochromeBillLayout;
