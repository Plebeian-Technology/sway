import { Link, usePage } from "@inertiajs/react";
import { ExternalLink } from "lucide-react";
import { useMemo } from "react";

import LazyBillSummaryMarkdown from "app/frontend/components/bill/layouts/LazyBillSummaryMarkdown";
import BillAsIntroduced from "app/frontend/components/bill/BillAsIntroduced";
import EmailLegislatorsModal from "app/frontend/components/bill/EmailLegislatorsModal";
import ShareBillButton from "app/frontend/components/bill/ShareBillButton";
import { ROUTES, VOTING_WEBSITES_BY_SWAY_LOCALE } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { useSwayLocaleSlug } from "app/frontend/hooks/useSwayLocales";
import BillAffinityPanel from "app/frontend/components/bill/charts/BillAffinityPanel";
import BillChartsPanel from "app/frontend/components/bill/charts/BillChartsPanel";
import {
    isVoteComparisonSuppressed,
    selectBillPositions,
    selectVoteTally,
} from "app/frontend/components/bill/sway_utils/billPositions";
import VoteComparisonPlaceholder from "app/frontend/components/bill/VoteComparisonPlaceholder";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { sway } from "sway";
import OrgPositionSummary from "app/frontend/components/bill/OrgPositionSummary";
import RelatedNewsArticles from "app/frontend/components/bill/RelatedNewsArticles";
import NewsArticleTestimony from "app/frontend/components/bill/NewsArticleTestimony";
import PublicTestimonySection from "app/frontend/components/bill/PublicTestimonySection";

import { hasValidSourceLink } from "app/frontend/components/bill/sway_utils/billSourceLink";

interface IProps {
    bill: sway.IBill;
    bill_score?: sway.IBillScore;
    isAwaitingScoreUpdate?: boolean;
    organizations: sway.IBillOrganizationPosition[];
    userVote?: sway.IUserVote;
    public_testimony_counts?: sway.IPublicTestimonyCounts | null;
    public_testimony_letters?: sway.IPublicTestimonyLetter[] | null;
}

const BillContent: React.FC<IProps> = ({
    bill,
    bill_score,
    isAwaitingScoreUpdate = false,
    organizations,
    userVote,
    public_testimony_counts,
    public_testimony_letters,
}) => {
    const {
        user,
        sway_locale,
        public_testimony_counts: pageCounts,
        public_testimony_letters: pageLetters,
    } = usePage<sway.IPageProps>().props;
    const swayLocaleSlug = useSwayLocaleSlug();
    const publicTestimonyCounts = public_testimony_counts ?? pageCounts;
    const publicTestimonyLetters = public_testimony_letters ?? pageLetters;
    const { supporting, opposing } = useMemo(
        () => selectBillPositions(organizations, bill.id),
        [bill.id, organizations],
    );
    const { forPercent, againstPercent } = selectVoteTally(bill_score);
    const comparisonSuppressed = isVoteComparisonSuppressed(bill_score);
    return (
        <div className="grid gap-6">
            <Card className="border-transparent bg-card/95" data-testid="score-panel">
                <CardHeader>
                    <CardTitle className="text-xl font-black">{PARITY_COPY.bill.content.howOthersVoted}</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                    {comparisonSuppressed ? (
                        <VoteComparisonPlaceholder showInvite />
                    ) : (
                        <div className="grid gap-3 sm:grid-cols-2">
                            <div className="rounded-xl bg-surface-3 px-4 py-4 shadow-neo">
                                <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                                    For
                                </div>
                                <div className="mt-2 text-3xl font-black text-vote-for">{forPercent}%</div>
                            </div>
                            <div className="rounded-xl bg-surface-3 px-4 py-4 shadow-neo">
                                <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                                    Against
                                </div>
                                <div className="mt-2 text-3xl font-black text-vote-against">{againstPercent}%</div>
                            </div>
                        </div>
                    )}

                    {isAwaitingScoreUpdate && (
                        <p className="text-sm font-semibold text-muted-foreground">
                            Waiting for the latest score update…
                        </p>
                    )}
                </CardContent>
            </Card>

            <BillChartsPanel bill={bill} bill_score={bill_score} isAwaitingScoreUpdate={isAwaitingScoreUpdate} />

            <BillAffinityPanel bill_score={bill_score} />

            <Card className="bg-card/95">
                <CardHeader>
                    <CardTitle className="text-xl font-black">{PARITY_COPY.bill.content.swaysSummary}</CardTitle>
                </CardHeader>
                <CardContent className="prose prose-sm max-w-none text-foreground">
                    <LazyBillSummaryMarkdown
                        summary={bill.summary}
                        aiUnreviewed={bill.summary_ai_unreviewed}
                        billId={bill.id}
                        billLink={bill.link}
                    />
                </CardContent>
            </Card>

            <RelatedNewsArticles articles={bill.related_articles} variant="default" />

            {(supporting.length > 0 || opposing.length > 0) && (
                // @lat: [[organization-affiliation-labels#Organization affiliation labels#The bill page carries the notice once]]
                <p className="text-sm text-muted-foreground">{PARITY_COPY.orgs.listNotice}</p>
            )}

            <div className="grid gap-6 lg:grid-cols-2">
                <Card className="bg-card/95">
                    <CardHeader>
                        <CardTitle className="text-xl font-black">{PARITY_COPY.bill.content.whySupport}</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                        {supporting.length ? (
                            supporting.map(({ org, position }) => (
                                <div
                                    key={`${org.name}-${position.id}`}
                                    data-neo-surface="true"
                                    className="rounded-xl px-4 py-4"
                                >
                                    <p className="text-sm font-black text-foreground">{org.name}</p>
                                    <OrgPositionSummary
                                        summary={position.summary}
                                        summaryAiUnreviewed={position.summary_ai_unreviewed}
                                        className="mt-2 text-sm leading-6 text-muted-foreground"
                                        organizationName={org.name}
                                        sourceKind={position.source_kind}
                                    />
                                </div>
                            ))
                        ) : (
                            <p className="text-sm leading-6 text-muted-foreground">{PARITY_COPY.org.noSupport}</p>
                        )}
                        <NewsArticleTestimony testimonies={bill.news_testimonies} stance="support" variant="default" />
                    </CardContent>
                </Card>

                <Card className="bg-card/95">
                    <CardHeader>
                        <CardTitle className="text-xl font-black">{PARITY_COPY.bill.content.whyOppose}</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                        {opposing.length ? (
                            opposing.map(({ org, position }) => (
                                <div
                                    key={`${org.name}-${position.id}`}
                                    data-neo-surface="true"
                                    className="rounded-xl px-4 py-4"
                                >
                                    <p className="text-sm font-black text-foreground">{org.name}</p>
                                    <OrgPositionSummary
                                        summary={position.summary}
                                        summaryAiUnreviewed={position.summary_ai_unreviewed}
                                        className="mt-2 text-sm leading-6 text-muted-foreground"
                                        organizationName={org.name}
                                        sourceKind={position.source_kind}
                                    />
                                </div>
                            ))
                        ) : (
                            <p className="text-sm leading-6 text-muted-foreground">{PARITY_COPY.org.noOppose}</p>
                        )}
                        <NewsArticleTestimony testimonies={bill.news_testimonies} stance="oppose" variant="default" />
                    </CardContent>
                </Card>
            </div>

            <PublicTestimonySection
                counts={publicTestimonyCounts}
                letters={publicTestimonyLetters}
                billTitle={bill.title}
                billId={bill.id}
                canOverrideStance={Boolean(user?.is_sway_admin)}
            />

            <Card className="bg-card/95" data-testid={userVote ? "legislator-comparison" : undefined}>
                <CardHeader>
                    <CardTitle className="text-xl font-black">{PARITY_COPY.bill.content.takeNextStep}</CardTitle>
                </CardHeader>
                <CardContent className="flex flex-wrap gap-3">
                    {userVote && (
                        <>
                            <Link
                                href={ROUTES.legislators}
                                className="inline-flex cursor-pointer rounded-xl border-neo border-border-strong bg-surface-3 px-4 py-3 text-sm font-semibold text-foreground shadow-neo transition hover:bg-accent"
                            >
                                {PARITY_COPY.bill.compareWithReps}
                            </Link>
                            <Link
                                href={ROUTES.pastBills}
                                className="inline-flex cursor-pointer rounded-xl border-neo border-border-strong bg-surface-3 px-4 py-3 text-sm font-semibold text-foreground shadow-neo transition hover:bg-accent"
                            >
                                {PARITY_COPY.bill.voteOnPastLegislation}
                            </Link>
                            {bill.active !== false && <EmailLegislatorsModal bill={bill} />}
                        </>
                    )}

                    <ShareBillButton bill={bill} />

                    {/* @lat: [[unlinked-bill-presentation#Cross-platform parity in unlinked presentation]] */}
                    {hasValidSourceLink(bill.link, sway_locale?.generic_portal_urls) ? (
                        <a
                            href={bill.link as string}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center gap-2 rounded-xl border-neo border-border bg-primary px-4 py-3 text-sm font-semibold text-primary-foreground shadow-neo transition"
                        >
                            {(swayLocaleSlug &&
                                (VOTING_WEBSITES_BY_SWAY_LOCALE as Record<string, string>)[swayLocaleSlug]) ||
                                "Official Source"}
                            <ExternalLink className="size-4" aria-hidden="true" />
                        </a>
                    ) : (
                        <p
                            data-testid="no-source-link"
                            className="flex items-center text-xs font-semibold text-muted-foreground"
                        >
                            {PARITY_COPY.bill.officialSourceUnavailable}
                        </p>
                    )}
                </CardContent>
            </Card>

            {/* @lat: [[user-vote-submission#Themed web vote controls#Where the default control sits]] */}
            <BillAsIntroduced title={bill.title} />
        </div>
    );
};

export default BillContent;
