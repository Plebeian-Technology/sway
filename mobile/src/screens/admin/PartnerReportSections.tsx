// @lat: [[mobile-admin-area#The partner reports screen]]
import React from "react";
import { Linking, Text, View } from "react-native";

import { Card } from "../../components/ui/Card";
import type { PartnerArticleReport, PartnerReport } from "../../hooks/admin/usePartnerReports";
import { isSafeCitationUrl } from "../../utils/safeUrl";

const SUPPRESSED_LABEL = "Suppressed (k < 5)";

const formatDate = (value: string | null): string => {
    if (!value) return "N/A";
    const date = new Date(value);
    return isNaN(date.getTime())
        ? value
        : date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
};

const isPartnerSuppressed = (partner: PartnerReport) => partner.sentiment_suppressed ?? partner.total_votes < 5;

const partnerSentiment = (partner: PartnerReport): string => {
    if (isPartnerSuppressed(partner)) return SUPPRESSED_LABEL;
    if (partner.pro_percentage !== null) return `${partner.pro_percentage}% Pro / ${partner.con_percentage}% Con`;
    return "N/A";
};

const articleSentiment = (article: PartnerArticleReport): string =>
    article.sentiment_suppressed
        ? SUPPRESSED_LABEL
        : `${article.pro_votes_count ?? 0} Pro / ${article.con_votes_count ?? 0} Con`;

const sum = (partners: PartnerReport[], pick: (partner: PartnerReport) => number) =>
    partners.reduce((total, partner) => total + pick(partner), 0);

export const SectionHeading = ({ title, description }: { title: string; description: string }) => (
    <View className="px-4 pt-2 pb-3">
        <Text className="text-lg font-open-sans-semibold text-foreground-light dark:text-foreground-dark">{title}</Text>
        <Text className="mt-1 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
            {description}
        </Text>
    </View>
);

const Figure = ({ label, value, note }: { label: string; value: string; note: string }) => (
    <Card className="mx-4 mb-3">
        <Text className="text-sm font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
            {label}
        </Text>
        <Text className="text-2xl font-open-sans-bold text-foreground-light dark:text-foreground-dark">{value}</Text>
        <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
            {note}
        </Text>
    </Card>
);

export const HeadlineFigures = ({ partners, single }: { partners: PartnerReport[]; single: boolean }) => {
    const totalClicks = sum(partners, (partner) => partner.total_clicks);
    const totalRegistrations = sum(partners, (partner) => partner.total_registrations);
    const only = single ? partners[0] : undefined;

    let votesNote = "Constituent votes on covered bills";
    if (only) {
        if (isPartnerSuppressed(only)) votesNote = SUPPRESSED_LABEL;
        else if (only.pro_percentage !== null) votesNote = `${only.pro_percentage}% Pro / ${only.con_percentage}% Con`;
    }

    return (
        <>
            <Figure
                label={only ? "Articles & Bills" : "Total Articles"}
                value={String(sum(partners, (partner) => partner.articles_count))}
                note={
                    only ? `Across ${only.bills_count} distinct bills` : `Across ${partners.length} partner newsrooms`
                }
            />
            <Figure
                label="Total Clicks"
                value={totalClicks.toLocaleString()}
                note="Inbound reader referrals from embeds"
            />
            <Figure
                label="Registrations"
                value={totalRegistrations.toLocaleString()}
                note={
                    totalClicks > 0
                        ? `${((totalRegistrations / totalClicks) * 100).toFixed(1)}% click-to-register conversion`
                        : "Verified constituent accounts created"
                }
            />
            <Figure
                label="Votes Cast"
                value={sum(partners, (partner) => partner.total_votes).toLocaleString()}
                note={votesNote}
            />
        </>
    );
};

export const PartnerCard = ({ partner, onPress }: { partner: PartnerReport; onPress: () => void }) => (
    <Card testID={`admin-partner-report-${partner.partner_slug}`} className="mx-4 mb-3" onPress={onPress}>
        <View>
            <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {partner.partner_name}
            </Text>
            <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                {partner.partner_slug}
            </Text>
        </View>
        <Text className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark">
            {`${partner.articles_count} articles · ${partner.bills_count} bills`}
        </Text>
        <Text className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark">
            {`${partner.total_clicks.toLocaleString()} clicks · ${partner.total_registrations.toLocaleString()} registrations · ${partner.total_votes.toLocaleString()} votes`}
        </Text>
        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
            {partnerSentiment(partner)}
        </Text>
    </Card>
);

const ArticleCard = ({ article, partnerName }: { article: PartnerArticleReport; partnerName?: string }) => {
    return (
        <Card className="mx-4 mb-3">
            {isSafeCitationUrl(article.article_url) ? (
                <Text
                    accessibilityRole="link"
                    onPress={() => void Linking.openURL(article.article_url).catch(() => {})}
                    className="text-base font-open-sans-semibold text-foreground-light underline dark:text-foreground-dark"
                >
                    {article.article_title}
                </Text>
            ) : (
                <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {article.article_title}
                </Text>
            )}
            {article.bill_title ? (
                <Text
                    numberOfLines={1}
                    className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                >
                    {`Bill: ${article.bill_title}`}
                </Text>
            ) : null}
            {partnerName ? (
                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {partnerName}
                </Text>
            ) : null}
            <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                {formatDate(article.published_at)}
            </Text>
            <Text className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark">
                {`${article.clicks_count.toLocaleString()} clicks · ${article.registrations_count.toLocaleString()} registrations · ${article.votes_count.toLocaleString()} votes`}
            </Text>
            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                {articleSentiment(article)}
            </Text>
        </Card>
    );
};

export const CoveredArticles = ({ partners, single }: { partners: PartnerReport[]; single: boolean }) => {
    const articles = partners.flatMap((partner) =>
        partner.articles.map((article) => ({ article, partnerName: single ? undefined : partner.partner_name })),
    );
    return (
        <>
            <SectionHeading
                title="Covered Articles"
                description="Individual articles embedding Sway widgets with attribution, conversion, and k-anonymity sentiment. k < 5 votes suppresses sentiment to protect voter privacy."
            />
            {articles.length === 0 ? (
                <Text className="px-4 py-6 text-center text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    No articles recorded for this partner yet.
                </Text>
            ) : (
                articles.map(({ article, partnerName }) => (
                    <ArticleCard key={article.id} article={article} partnerName={partnerName} />
                ))
            )}
        </>
    );
};
