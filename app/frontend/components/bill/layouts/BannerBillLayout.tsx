import { Link, usePage } from "@inertiajs/react";
import type { sway } from "sway";

import BillAsIntroduced from "app/frontend/components/bill/BillAsIntroduced";
import BillSponsorLink from "app/frontend/components/bill/BillSponsorLink";
import LazyBillSummaryMarkdown from "app/frontend/components/bill/layouts/LazyBillSummaryMarkdown";
import BillEntryTitle from "app/frontend/components/bill/list-layouts/BillEntryTitle";
import EmailLegislatorsModal from "app/frontend/components/bill/EmailLegislatorsModal";
import ShareBillButton from "app/frontend/components/bill/ShareBillButton";
import VotePanel from "app/frontend/components/bill/VotePanel";
import { useSwayLocaleSlug } from "app/frontend/hooks/useSwayLocales";
import { ROUTES, Support } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import {
    isVoteComparisonSuppressed,
    selectBillPositions,
    selectVoteMajority,
    selectVoteTally,
} from "app/frontend/components/bill/sway_utils/billPositions";
import VoteComparisonPlaceholder from "app/frontend/components/bill/VoteComparisonPlaceholder";
import { briefSummary } from "app/frontend/components/bill/sway_utils/billTitle";
import { toFormattedLocaleName } from "app/frontend/sway_utils/locales";
import { formatDate } from "app/frontend/sway_utils/datetimes";

import "app/frontend/components/bill/layouts/banner-bill-layout.css";
import type { BillLayoutProps } from "app/frontend/components/bill/layouts/types";
import OrgPositionSummary from "app/frontend/components/bill/OrgPositionSummary";
import PublicTestimonySection from "app/frontend/components/bill/PublicTestimonySection";
import RelatedNewsArticles from "app/frontend/components/bill/RelatedNewsArticles";
import NewsArticleTestimony from "app/frontend/components/bill/NewsArticleTestimony";

const monogram = (name: string): string => {
    const parts = name.trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return "";
    const first = parts[0][0] ?? "";
    const last = parts.length > 1 ? parts[parts.length - 1][0] : "";
    return (first + last).toUpperCase();
};

// @lat: [[vote-majority-vocabulary#Implementation]]
const BannerBillLayout: React.FC<BillLayoutProps> = ({ bill, sponsor, organizations, user_vote, bill_score }) => {
    const { user, public_testimony_counts, public_testimony_letters } = usePage<sway.IPageProps>().props;
    const swayLocaleSlug = useSwayLocaleSlug();
    const jurisdiction = swayLocaleSlug ? toFormattedLocaleName(swayLocaleSlug, false) : "Sway";
    const status = bill.vote_date_time_utc ? `Voted ${formatDate(bill.vote_date_time_utc)}` : "Awaiting a final vote";
    const dek = briefSummary(bill.summary, 220);

    const { all: positions } = selectBillPositions(organizations, bill.id);
    const { forCount, againstCount, total, forPct } = selectVoteTally(bill_score);

    const { userVoted, userSupports, majorityStatus, withMajority } = selectVoteMajority(user_vote, {
        forCount,
        againstCount,
        total,
        forPct,
    });

    const comparisonSuppressed = isVoteComparisonSuppressed(bill_score);

    let verdict: React.ReactNode = null;
    if (!comparisonSuppressed && withMajority !== null) {
        verdict = withMajority ? (
            <p>
                Your vote stands <em>with</em> the current majority.
            </p>
        ) : (
            <p>
                Your vote stands <em>against</em> the current majority.
            </p>
        );
    }

    return (
        <div className="bn-stage">
            <div className="bn-topbar">
                <Link className="bn-back" href={ROUTES.pastBills}>
                    ← All bills
                </Link>
                <span className="bn-edition">Banner edition</span>
            </div>

            <main className="bn-main">
                <div className="bn-crumb">
                    <span className="bn-kicker">{jurisdiction}</span>
                    {bill.chamber && (
                        <>
                            <span className="bn-sep">/</span>
                            <span className="bn-kicker">{titleize(bill.chamber)}</span>
                        </>
                    )}
                    {bill.categories?.length ? (
                        <>
                            <span className="bn-sep">/</span>
                            <span className="bn-cat">{bill.categories.join(" · ")}</span>
                        </>
                    ) : null}
                </div>

                <header className="bn-head">
                    <div className="bn-billno">Bill {bill.external_id}</div>
                    <h1 className="bn-title" data-testid="bill-title">
                        <BillEntryTitle title={bill.title} qualifierClassName="bn-title__qualifier" />
                    </h1>
                    {dek && <p className="bn-dek">{dek}</p>}
                </header>

                <div className="bn-byline">
                    {sponsor && (
                        <span className="bn-by">
                            <span className="bn-avatar" aria-hidden="true">
                                {monogram(sponsor.full_name)}
                            </span>
                            Introduced by{" "}
                            <BillSponsorLink legislatorId={bill.legislator_id} className="bn-link">
                                <b>{sponsor.full_name}</b>
                            </BillSponsorLink>
                        </span>
                    )}
                    <span className="bn-status">{status}</span>
                </div>

                <section className="bn-results">
                    <div className="bn-kicker bn-results__k">You &amp; the vote</div>
                    <div className="bn-twovote">
                        <div className="bn-v">
                            <div className="bn-who">Your vote</div>
                            <div
                                className={`bn-pos ${
                                    userVoted ? (userSupports ? "bn-pos--for" : "bn-pos--against") : "bn-pos--none"
                                }`}
                            >
                                {userVoted ? (userSupports ? "For" : "Against") : "Not yet cast"}
                            </div>
                        </div>
                        {!comparisonSuppressed && (
                            <div className="bn-v">
                                <div className="bn-who">Where it stands</div>
                                <div className="bn-pos">{majorityStatus}</div>
                            </div>
                        )}
                    </div>

                    {verdict && <div className="bn-verdict">{verdict}</div>}

                    {comparisonSuppressed ? (
                        <VoteComparisonPlaceholder showInvite />
                    ) : (
                        <div className="bn-tallies">
                            <div className="bn-tally">
                                <div className="bn-tl">In support</div>
                                <div className="bn-tn">
                                    {forCount.toLocaleString()} <span className="bn-u">residents</span>
                                </div>
                                <div className="bn-bar" aria-hidden="true">
                                    <span style={{ width: `${forPct}%` }} />
                                </div>
                            </div>
                            <div className="bn-tally">
                                <div className="bn-tl">Opposed</div>
                                <div className="bn-tn">
                                    {againstCount.toLocaleString()} <span className="bn-u">residents</span>
                                </div>
                            </div>
                        </div>
                    )}

                    <div className="bn-action">
                        <VotePanel bill={bill} user_vote={user_vote} />
                        <div className="mt-4 flex flex-wrap gap-3">
                            <ShareBillButton bill={bill} />
                            {user_vote && bill.active !== false && <EmailLegislatorsModal bill={bill} />}
                        </div>
                    </div>
                </section>

                <section className="bn-section bn-prose">
                    <div className="bn-eyebrow">In plain language</div>
                    <LazyBillSummaryMarkdown
                        summary={bill.summary}
                        aiUnreviewed={bill.summary_ai_unreviewed}
                        billId={bill.id}
                        billLink={bill.link}
                    />
                </section>

                <RelatedNewsArticles articles={bill.related_articles} variant="banner" />

                <section className="bn-section">
                    <div className="bn-eyebrow">Where organizations stand</div>
                    <div className="bn-provisions">
                        {positions.length ? (
                            positions.map(({ org, position }, i) => (
                                <article key={org.id} className="bn-prov">
                                    <div className="bn-num" aria-hidden="true">
                                        {i + 1}
                                    </div>
                                    <div>
                                        <h3>{org.name}</h3>
                                        <OrgPositionSummary
                                            summary={position.summary}
                                            summaryAiUnreviewed={position.summary_ai_unreviewed}
                                            prefix={position.support === Support.For ? "In support." : "In opposition."}
                                        />
                                    </div>
                                </article>
                            ))
                        ) : (
                            <p className="bn-empty">No organizations have filed a position on this bill.</p>
                        )}
                    </div>
                    <NewsArticleTestimony testimonies={bill.news_testimonies} variant="banner" />
                </section>

                <PublicTestimonySection
                    counts={public_testimony_counts}
                    letters={public_testimony_letters}
                    billTitle={bill.title}
                    billId={bill.id}
                    canOverrideStance={Boolean(user?.is_sway_admin)}
                />

                {/* @lat: [[bill-as-introduced-title-split#Why BillAsIntroduced exists]] */}
                <BillAsIntroduced title={bill.title} />
            </main>

            <footer className="bn-foot">
                <p>
                    <span className="bn-mark">Sway</span> — vote on the same legislation as your representatives, then
                    see whether you agreed.
                </p>
            </footer>
        </div>
    );
};

export default BannerBillLayout;
