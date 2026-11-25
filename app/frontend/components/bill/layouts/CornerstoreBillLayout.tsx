import { usePage } from "@inertiajs/react";
import type { sway } from "sway";

import BillSponsorLink from "app/frontend/components/bill/BillSponsorLink";
import LazyBillSummaryMarkdown from "app/frontend/components/bill/layouts/LazyBillSummaryMarkdown";
import CornerstoreVotePanel from "app/frontend/components/bill/CornerstoreVotePanel";
import EmailLegislatorsModal from "app/frontend/components/bill/EmailLegislatorsModal";
import ShareBillButton from "app/frontend/components/bill/ShareBillButton";
import SwayLocaleFlag from "app/frontend/components/locales/SwayLocaleFlag";
import { useSwayLocaleSlug } from "app/frontend/hooks/useSwayLocales";
import { Support } from "app/frontend/sway_constants";
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

import "app/frontend/components/bill/layouts/cornerstore-bill-layout.css";
import type { BillLayoutProps } from "app/frontend/components/bill/layouts/types";
import OrgPositionSummary from "app/frontend/components/bill/OrgPositionSummary";
import PublicTestimonySection from "app/frontend/components/bill/PublicTestimonySection";
import RelatedNewsArticles from "app/frontend/components/bill/RelatedNewsArticles";
import NewsArticleTestimony from "app/frontend/components/bill/NewsArticleTestimony";

// @lat: [[theme-driven-bill-layout-selection#Why BallotBillLayout.tsx and CornerstoreBillLayout.tsx look the way they do]]
const CornerstoreBillLayout: React.FC<BillLayoutProps> = ({ bill, sponsor, organizations, user_vote, bill_score }) => {
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
        <div className="cs-stage">
            <div className="cs-masthead">
                {swayLocaleSlug && <SwayLocaleFlag swayLocaleSlug={swayLocaleSlug} className="cs-masthead__flag" />}
                <div className="cs-kicker">On the floor</div>
            </div>

            <h1 className="cs-headline" data-testid="bill-title">
                {headline}
            </h1>
            {deck && <p className="cs-deck">{deck}</p>}

            <p className="cs-longtitle">
                <b>
                    {jurisdiction} {bill.external_id}
                </b>{" "}
                — {bill.title}
            </p>

            <div className="cs-chips">
                <span className="cs-chip cs-chip--code">{bill.external_id}</span>
                {bill.chamber && <span className="cs-chip">{titleize(bill.chamber)}</span>}
                {bill.categories?.map((category) => (
                    <span key={category} className="cs-chip">
                        {category}
                    </span>
                ))}
            </div>

            <CornerstoreVotePanel bill={bill} user_vote={user_vote} />
            <div className="cs-followup flex flex-wrap gap-3">
                <ShareBillButton bill={bill} />
                {user_vote && bill.active !== false && <EmailLegislatorsModal bill={bill} />}
            </div>

            <div className="cs-grid">
                <div className="cs-card">
                    <h2 className="cs-card__title">What it does</h2>
                    <div className="cs-prose">
                        <LazyBillSummaryMarkdown
                            summary={bill.summary}
                            aiUnreviewed={bill.summary_ai_unreviewed}
                            billId={bill.id}
                            billLink={bill.link}
                        />
                    </div>
                </div>

                <div className="cs-side">
                    {sponsor && (
                        <div className="cs-card">
                            <h2 className="cs-card__title">Sponsor</h2>
                            <BillSponsorLink legislatorId={bill.legislator_id} className="cs-sponsor">
                                {sponsor.full_name}
                            </BillSponsorLink>
                            <p className="cs-note">
                                Sway records the sponsor and any co-sponsors as voting For when a roll-call vote is not
                                yet available.
                            </p>
                            <p className="cs-note">{status}</p>
                        </div>
                    )}

                    <div className="cs-card">
                        <h2 className="cs-card__title">The count</h2>
                        {comparisonSuppressed ? (
                            <VoteComparisonPlaceholder showInvite />
                        ) : (
                            <>
                                <div className="cs-tally">
                                    <span className="cs-tally__n">{forPercent}%</span>
                                    <span className="cs-tally__l">for</span>
                                </div>
                                <div className="cs-tally">
                                    <span className="cs-tally__n">{againstPercent}%</span>
                                    <span className="cs-tally__l">against</span>
                                </div>
                            </>
                        )}
                    </div>
                </div>
            </div>

            <RelatedNewsArticles articles={bill.related_articles} variant="cornerstore" />

            <div className="cs-card cs-card--wide">
                <h2 className="cs-card__title">Who&rsquo;s for it, who&rsquo;s against</h2>
                {positions.length ? (
                    <ul className="cs-orgs">
                        {positions.map(({ org, position }) => (
                            <li key={org.id} className="cs-org">
                                <span
                                    className={`cs-org__stance cs-org__stance--${
                                        position.support === Support.For ? "for" : "against"
                                    }`}
                                >
                                    {position.support === Support.For ? "For" : "Against"}
                                </span>
                                <div>
                                    <h3 className="cs-org__name">{org.name}</h3>
                                    <OrgPositionSummary
                                        summary={position.summary}
                                        summaryAiUnreviewed={position.summary_ai_unreviewed}
                                        className="cs-org__summary"
                                    />
                                </div>
                            </li>
                        ))}
                    </ul>
                ) : (
                    <p className="cs-empty">No statements of support or opposition are on file yet.</p>
                )}
                <NewsArticleTestimony testimonies={bill.news_testimonies} variant="cornerstore" />
            </div>

            <PublicTestimonySection
                counts={public_testimony_counts}
                letters={public_testimony_letters}
                billTitle={bill.title}
                billId={bill.id}
                canOverrideStance={Boolean(user?.is_sway_admin)}
            />
        </div>
    );
};

export default CornerstoreBillLayout;
