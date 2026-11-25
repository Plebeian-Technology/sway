// @lat: [[mobile-bill-surface-components-design#BillScreenTabs]]
import React, { useState } from "react";
import { Pressable as RNPressable, Text, View } from "react-native";
import { Flag } from "lucide-react-native";

import { AuthPromptSheet } from "./AuthPromptSheet";
import BillSectionTabs from "./BillSectionTabs";
import { BillAsIntroduced } from "./BillAsIntroduced";
import { BillHeader } from "./BillHeader";
import { BillScoreBar } from "./BillScoreBar";
import { BillSummarySection } from "./BillSummarySection";
import { BillVoteStatus } from "./BillVoteStatus";
import { DistrictVotesPanel } from "./DistrictVotesPanel";
import { HearingTestimonySection } from "./HearingTestimonySection";
import { OrgPositionsSection, type OrgPosition } from "./OrgPositionsSection";
import { PublicTestimonySection, hasPublicTestimony } from "./PublicTestimonySection";
import { RelatedNewsArticles } from "./RelatedNewsArticles";
import { ReportSummarySheet } from "./ReportSummarySheet";
import { SkeletonCard } from "./SkeletonCard";
import { VoteComparisonPlaceholder } from "./VoteComparisonPlaceholder";
import { VotePanel } from "./VotePanel";
import { Card } from "./ui/Card";
import { EmptyState } from "./ui/EmptyState";
import { FadeInItem } from "./ui/FadeInItem";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { billHeadline, hasMoreThanHeadline } from "../utils/billTitle";
import {
    isVoteComparisonSuppressed,
    selectDistrictVotes,
    type BillScoreDistrict,
    type DistrictRef,
} from "../utils/districtVotes";
import type { NewsArticleTestimony, PublicTestimonyCounts, RelatedNewsArticle } from "../types/bill";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { isArchivedHistoricalBill } from "../../../app/frontend/components/bill/sway_utils/billArchiving";

const tabContentStyle = { gap: 16, paddingTop: 16 };

export interface BillScreenTabsBill {
    id: number;
    title: string;
    bill_number?: string;
    external_id?: string;
    chamber?: string;
    summary?: string | null;
    summary_ai_unreviewed?: boolean;
    status?: string;
    status_color?: string;
    link?: string | null;
    legislator_id?: number | null;
    categories?: string[];
    active?: boolean;
    scheduled_release_date_utc?: string | null;
    vote_date_time_utc?: string | null;
    house_vote_date_time_utc?: string | null;
    senate_vote_date_time_utc?: string | null;
    related_articles?: RelatedNewsArticle[];
    news_testimonies?: NewsArticleTestimony[];
}

type UserVote = { support?: "for" | "against" | "FOR" | "AGAINST" | null } | null;

export interface BillScreenTabsBillScore {
    for?: number | null;
    against?: number | null;
    comparison_suppressed?: boolean | null;
    voters_needed?: number | null;
    districts?: BillScoreDistrict[] | null;
}

export interface BillScreenTabsProps {
    bill: BillScreenTabsBill;
    sponsor: { full_name?: string } | null;
    userVote: UserVote;
    billScore: BillScreenTabsBillScore | null;
    organizations: OrgPosition[];
    readerDistricts: DistrictRef[];
    swayLocaleSlug: string;
    genericPortalUrls?: string[];
    publicTestimonyCounts?: PublicTestimonyCounts | null;
    isSignedIn: boolean;
    detailLoaded: boolean;
    detailError: Error | null;
    onRetry: () => void;
    onVoted: () => void;
    onNavigateToLegislators: () => void;
    onNavigateToBills: () => void;
    onSponsorPress?: () => void;
    hero?: boolean;
    heroTestID: string;
    summariesTestID: string;
}

const userSupportOf = (userVote: UserVote): "for" | "against" | null => {
    const s = userVote?.support;
    if (!s) return null;
    const lower = s.toString().toLowerCase();
    return lower === "for" || lower === "against" ? lower : null;
};

interface Section {
    key: string;
    node: React.ReactNode;
}

const section = (key: string, node: React.ReactNode): Section => ({ key, node });

const fadeIn = (sections: Section[]) =>
    sections
        .filter(({ node }) => !!node)
        .map(({ key, node }, index) => (
            <FadeInItem key={key} index={index}>
                {node}
            </FadeInItem>
        ));

const DetailErrorCard: React.FC<{ testID: string; onRetry: () => void }> = ({ testID, onRetry }) => (
    <Card>
        <EmptyState
            title={PARITY_COPY.bill.detailError}
            ctaLabel={PARITY_COPY.legislators.historyRetry}
            onCtaPress={onRetry}
            testID={testID}
            compact
        />
    </Card>
);

// @lat: [[bill-summary-reporting#Reader reporting of inaccurate summaries#Reporting from the mobile Bill tab]]
const ReportSummaryControl: React.FC<{ billId: number; isSignedIn: boolean }> = ({ billId, isSignedIn }) => {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const [open, setOpen] = useState(false);
    const close = () => setOpen(false);

    return (
        <>
            <RNPressable
                testID="btn-report-inaccurate-summary"
                accessibilityRole="button"
                accessibilityLabel={PARITY_COPY.bill.reportInaccurateSummary}
                onPress={() => setOpen(true)}
                className="flex-row items-center gap-2 self-start"
                style={{ minHeight: 44 }}
            >
                <Flag size={14} color={t.accent} />
                <Text className="shrink text-sm font-open-sans-semibold text-accent-light underline dark:text-accent-dark">
                    {PARITY_COPY.bill.reportInaccurateSummary}
                </Text>
            </RNPressable>
            {isSignedIn ? (
                <ReportSummarySheet visible={open} billId={billId} onClose={close} />
            ) : (
                <AuthPromptSheet
                    visible={open}
                    heading={PARITY_COPY.bill.reportInaccurateSummary}
                    body={PARITY_COPY.bill.reportDialogDescription}
                    onSignIn={close}
                    onDismiss={close}
                    testID="report-summary-auth-prompt"
                />
            )}
        </>
    );
};

export function BillScreenTabs({
    bill,
    sponsor,
    userVote,
    billScore,
    organizations,
    readerDistricts,
    swayLocaleSlug,
    genericPortalUrls,
    publicTestimonyCounts,
    isSignedIn,
    detailLoaded,
    detailError,
    onRetry,
    onVoted,
    onNavigateToLegislators,
    onNavigateToBills,
    onSponsorPress,
    hero = false,
    heroTestID,
    summariesTestID,
}: BillScreenTabsProps) {
    const relatedArticles = bill.related_articles ?? [];
    const detailFailed = !detailLoaded && !!detailError;
    const detailPending = !detailLoaded && !detailFailed;
    // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
    const comparisonSuppressed = isVoteComparisonSuppressed(billScore);
    const districtVotes = selectDistrictVotes(comparisonSuppressed ? [] : billScore?.districts, readerDistricts);
    const hasDistrictVotes = districtVotes.rows.length > 0 || districtVotes.readerRows.length > 0;
    const sponsorPress = bill.legislator_id != null ? onSponsorPress : undefined;
    const canReportSummary = Boolean(bill.id) && !isArchivedHistoricalBill(bill);

    const detailPlaceholder = (name: "votes" | "summaries"): React.ReactNode => {
        if (detailFailed) return <DetailErrorCard testID={`${name}-detail-error`} onRetry={onRetry} />;
        if (detailPending) return <SkeletonCard heightClass="h-40" testID={`${name}-skeleton`} />;
        return null;
    };

    const billSections = [
        section(
            "hero",
            <Card testID={heroTestID}>
                <BillHeader
                    bill={bill}
                    sponsor={sponsor}
                    hero={hero}
                    showVoteStatus={false}
                    onSponsorPress={sponsorPress}
                />
                <VotePanel bill={bill} user_vote={userVote} onVoted={onVoted} className="mt-2" />
                <BillVoteStatus bill={bill} />
            </Card>,
        ),
        section(
            "summary",
            <View>
                <BillSummarySection
                    summary={bill.summary}
                    summaryAiUnreviewed={bill.summary_ai_unreviewed}
                    showSourceNotice
                    billLink={bill.link}
                    swayLocaleSlug={swayLocaleSlug}
                    genericPortalUrls={genericPortalUrls}
                />
                {canReportSummary ? <ReportSummaryControl billId={bill.id} isSignedIn={isSignedIn} /> : null}
            </View>,
        ),
        section("as-introduced", hasMoreThanHeadline(bill.title) ? <BillAsIntroduced title={bill.title} /> : null),
    ];

    const votesSections = [
        section(
            "vote",
            <Card>
                <VotePanel bill={bill} user_vote={userVote} onVoted={onVoted} className="" />
            </Card>,
        ),
        section(
            "tally",
            detailPlaceholder("votes") ?? (
                <Card>
                    {comparisonSuppressed ? (
                        <VoteComparisonPlaceholder votersNeeded={billScore?.voters_needed} isSignedIn={isSignedIn} />
                    ) : (
                        <BillScoreBar bill_score={billScore} />
                    )}
                </Card>
            ),
        ),
        section(
            "districts",
            detailLoaded && !comparisonSuppressed && hasDistrictVotes ? (
                <Card>
                    <DistrictVotesPanel votes={districtVotes} userVoteSupport={userSupportOf(userVote)} />
                </Card>
            ) : null,
        ),
        section(
            "next-step",
            <HearingTestimonySection
                bill={bill}
                userVote={userVote}
                swayLocaleSlug={swayLocaleSlug}
                genericPortalUrls={genericPortalUrls}
                onNavigateToLegislators={onNavigateToLegislators}
                onNavigateToBills={onNavigateToBills}
                testID="take-next-step"
            />,
        ),
    ];

    // @lat: [[news-mobile-testimony#Zero-node suppression and screen lifecycle]]
    const summariesSections = [
        section("news", relatedArticles.length > 0 ? <RelatedNewsArticles articles={relatedArticles} /> : null),
        section(
            "positions",
            detailPlaceholder("summaries") ?? (
                <OrgPositionsSection positions={organizations} newsTestimonies={bill.news_testimonies} />
            ),
        ),
        section(
            "public-testimony",
            hasPublicTestimony(publicTestimonyCounts, isSignedIn) ? (
                <PublicTestimonySection
                    billId={bill.id}
                    counts={publicTestimonyCounts}
                    isSignedIn={isSignedIn}
                    billTitle={billHeadline(bill.title)}
                />
            ) : null,
        ),
    ];

    return (
        <BillSectionTabs
            key={bill.id}
            bill={
                <View style={tabContentStyle} testID="bill-tab-content">
                    {fadeIn(billSections)}
                </View>
            }
            votes={
                <View style={tabContentStyle} testID="votes-tab-content">
                    {fadeIn(votesSections)}
                </View>
            }
            summaries={
                <View style={tabContentStyle} testID={summariesTestID}>
                    {fadeIn(summariesSections)}
                </View>
            }
        />
    );
}

export default BillScreenTabs;
