import { Link, usePage } from "@inertiajs/react";
import type { sway } from "sway";

import BallotVotePanel from "app/frontend/components/bill/BallotVotePanel";
import BillSponsorLink from "app/frontend/components/bill/BillSponsorLink";
import LazyBillSummaryMarkdown from "app/frontend/components/bill/layouts/LazyBillSummaryMarkdown";
import EmailLegislatorsModal from "app/frontend/components/bill/EmailLegislatorsModal";
import ShareBillButton from "app/frontend/components/bill/ShareBillButton";
import SwayLocaleFlag from "app/frontend/components/locales/SwayLocaleFlag";
import { useSwayLocaleSlug } from "app/frontend/hooks/useSwayLocales";
import { ROUTES, Support } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import {
    isVoteComparisonSuppressed,
    selectBillPositions,
    selectVoteTally,
} from "app/frontend/components/bill/sway_utils/billPositions";
import VoteComparisonPlaceholder from "app/frontend/components/bill/VoteComparisonPlaceholder";
import { splitBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";
import { toFormattedLocaleName } from "app/frontend/sway_utils/locales";
import { formatDate } from "app/frontend/sway_utils/datetimes";

import "app/frontend/components/bill/layouts/ballot-bill-layout.css";
import type { BillLayoutProps } from "app/frontend/components/bill/layouts/types";
import OrgPositionSummary from "app/frontend/components/bill/OrgPositionSummary";
import PublicTestimonySection from "app/frontend/components/bill/PublicTestimonySection";
import RelatedNewsArticles from "app/frontend/components/bill/RelatedNewsArticles";
import NewsArticleTestimony from "app/frontend/components/bill/NewsArticleTestimony";

// @lat: [[theme-driven-bill-layout-selection#Why BallotBillLayout.tsx and CornerstoreBillLayout.tsx look the way they do]]
const BallotBillLayout: React.FC<BillLayoutProps> = ({ bill, sponsor, organizations, user_vote, bill_score }) => {
    const { user, public_testimony_counts, public_testimony_letters } = usePage<sway.IPageProps>().props;
    const swayLocaleSlug = useSwayLocaleSlug();
    const jurisdiction = swayLocaleSlug ? toFormattedLocaleName(swayLocaleSlug, false) : "Sway";
    const status = bill.vote_date_time_utc
        ? `Voted ${formatDate(bill.vote_date_time_utc)}`
        : "Legislators have not yet voted on a final version.";

    const { all: positions } = selectBillPositions(organizations, bill.id);
    const { forPercent, againstPercent } = selectVoteTally(bill_score);
    const comparisonSuppressed = isVoteComparisonSuppressed(bill_score);
    const { headline, deck } = splitBillTitle(bill.title);

    return (
        <div className="bal-sheet">
            <div className="bal-locale">
                {swayLocaleSlug && <SwayLocaleFlag swayLocaleSlug={swayLocaleSlug} className="bal-locale__flag" />}
                <strong>{jurisdiction}</strong>
                <Link href={ROUTES.pastBills} className="bal-locale__link">
                    All bills
                </Link>
            </div>

            <header className="bal-measure">
                <div className="bal-measure__code">
                    <span className="bal-code">{bill.external_id}</span>
                    {bill.chamber && <span className="bal-kind">{titleize(bill.chamber)} Bill</span>}
                </div>
                <h1 className="bal-shorttitle" data-testid="bill-title">
                    {headline}
                </h1>
                {deck && <p className="bal-deck">{deck}</p>}
            </header>

            <dl className="bal-meta">
                <div className="bal-meta__cell">
                    <dt>Status</dt>
                    <dd>{status}</dd>
                </div>
                {bill.categories?.length ? (
                    <div className="bal-meta__cell">
                        <dt>Categories</dt>
                        <dd>{bill.categories.join(" · ")}</dd>
                    </div>
                ) : null}
                {sponsor && (
                    <div className="bal-meta__cell">
                        <dt>Sponsor</dt>
                        <dd>
                            <BillSponsorLink legislatorId={bill.legislator_id} className="bal-sponsor">
                                {sponsor.full_name}
                            </BillSponsorLink>
                        </dd>
                    </div>
                )}
            </dl>

            <BallotVotePanel bill={bill} user_vote={user_vote} />
            <div className="bal-followup flex flex-wrap gap-3">
                <ShareBillButton bill={bill} />
                {user_vote && bill.active !== false && <EmailLegislatorsModal bill={bill} />}
            </div>

            <section className="bal-section">
                <h2 className="bal-sectionlabel">Sway summary</h2>
                <div className="bal-prose">
                    <LazyBillSummaryMarkdown
                        summary={bill.summary}
                        aiUnreviewed={bill.summary_ai_unreviewed}
                        billId={bill.id}
                        billLink={bill.link}
                    />
                </div>
            </section>

            <RelatedNewsArticles articles={bill.related_articles} variant="ballot" />

            <section className="bal-section">
                <h2 className="bal-sectionlabel">The count</h2>
                {comparisonSuppressed ? (
                    <VoteComparisonPlaceholder showInvite />
                ) : (
                    <div className="bal-count">
                        <div className="bal-count__cell">
                            <span className="bal-count__n">{forPercent}%</span>
                            <span className="bal-count__l">voted for</span>
                        </div>
                        <div className="bal-count__cell">
                            <span className="bal-count__n">{againstPercent}%</span>
                            <span className="bal-count__l">voted against</span>
                        </div>
                    </div>
                )}
            </section>

            <section className="bal-section">
                <h2 className="bal-sectionlabel">Support &amp; opposition</h2>
                {positions.length ? (
                    <ul className="bal-orgs">
                        {positions.map(({ org, position }) => (
                            <li key={org.id} className="bal-org">
                                <span className="bal-org__stance">
                                    {position.support === Support.For ? "For" : "Against"}
                                </span>
                                <div>
                                    <h3 className="bal-org__name">{org.name}</h3>
                                    <OrgPositionSummary
                                        summary={position.summary}
                                        summaryAiUnreviewed={position.summary_ai_unreviewed}
                                        className="bal-org__summary"
                                    />
                                </div>
                            </li>
                        ))}
                    </ul>
                ) : (
                    <p className="bal-empty">
                        Sway has not yet found statements of support or opposition for this legislation.
                    </p>
                )}
                <NewsArticleTestimony testimonies={bill.news_testimonies} variant="ballot" />
            </section>

            <PublicTestimonySection
                counts={public_testimony_counts}
                letters={public_testimony_letters}
                billTitle={bill.title}
                billId={bill.id}
                canOverrideStance={Boolean(user?.is_sway_admin)}
            />

            <section className="bal-section">
                <h2 className="bal-sectionlabel">As introduced</h2>
                <p className="bal-longtitle">{bill.title}</p>
            </section>
        </div>
    );
};

export default BallotBillLayout;
