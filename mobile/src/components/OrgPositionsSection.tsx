// @lat: [[mobile-org-membership-components-design#OrgPositionsSection]]
import React from "react";
import { Text, View } from "react-native";
import { Card, CardContent, CardHeader, CardTitle } from "./ui/Card";
import { Markdown } from "./Markdown";
import { NewsArticleTestimony } from "./NewsArticleTestimony";
import { PositionSourceLine } from "./PositionSourceLine";
import type { NewsArticleTestimony as NewsArticleTestimonyType } from "../types/bill";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface OrgPosition {
    id: number;
    support: "FOR" | "AGAINST";
    organization?: { name: string };
    summary?: string | null;
    summary_ai_unreviewed?: boolean;
    // @lat: [[news-org-position-persistence#Position origin and affiliation]]
    source_kind?: "hearing_testimony" | "news_article" | "sway_admin" | "organization" | null;
    source_url?: string | null;
}

export interface OrgPositionsSectionProps {
    positions?: OrgPosition[];
    newsTestimonies?: NewsArticleTestimonyType[];
    onOpenUrl?: (url: string) => void | Promise<void>;
    testID?: string;
}

interface StanceCardProps {
    title: string;
    emptyLabel: string;
    emptyTestID: string;
    stance: "support" | "oppose";
    positions: OrgPosition[];
    newsTestimonies?: NewsArticleTestimonyType[];
    onOpenUrl?: (url: string) => void | Promise<void>;
}

function StanceCard({
    title,
    emptyLabel,
    emptyTestID,
    stance,
    positions,
    newsTestimonies,
    onOpenUrl,
}: StanceCardProps) {
    return (
        <Card>
            <CardHeader>
                <CardTitle>{title}</CardTitle>
            </CardHeader>
            <CardContent className="gap-4">
                {positions.length > 0 ? (
                    positions.map((pos) => (
                        <View key={pos.id} className="bg-surface-2-light dark:bg-surface-2-dark rounded-xl px-4 py-4">
                            <Text
                                selectable
                                testID="org-position-name"
                                className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                            >
                                {pos.organization?.name}
                            </Text>
                            {/* @lat: [[organization-affiliation-labels#Organization affiliation labels#Every position carries its own tag]] */}
                            <Text
                                testID="org-position-source-tag"
                                className="text-xs font-open-sans-semibold uppercase text-muted-foreground-light dark:text-muted-foreground-dark mt-1"
                            >
                                {pos.source_kind === "organization" && pos.organization
                                    ? PARITY_COPY.orgs.postedBy(pos.organization.name)
                                    : PARITY_COPY.orgs.compiledBySway}
                            </Text>
                            <PositionSourceLine
                                sourceKind={pos.source_kind}
                                sourceUrl={pos.source_url}
                                onOpenUrl={onOpenUrl}
                            />
                            <View className="mt-2 gap-1">
                                <Markdown
                                    selectable
                                    content={pos.summary}
                                    onOpenUrl={onOpenUrl}
                                    className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                                />
                                {pos.summary_ai_unreviewed ? (
                                    <Text
                                        testID="ai-unreviewed-notice"
                                        className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                                    >
                                        {PARITY_COPY.bill.aiUnreviewedNotice}
                                    </Text>
                                ) : null}
                            </View>
                        </View>
                    ))
                ) : (
                    <Text
                        testID={emptyTestID}
                        className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                    >
                        {emptyLabel}
                    </Text>
                )}
                <NewsArticleTestimony testimonies={newsTestimonies} stance={stance} onOpenUrl={onOpenUrl} />
            </CardContent>
        </Card>
    );
}

export function OrgPositionsSection({ positions = [], newsTestimonies, onOpenUrl, testID }: OrgPositionsSectionProps) {
    const summarised = positions.filter((p) => p.summary);
    const supporting = summarised.filter((p) => p.support === "FOR");
    const opposing = summarised.filter((p) => p.support === "AGAINST");

    return (
        <View testID={testID ?? "org-positions-section"} className="gap-4">
            {/* @lat: [[organization-affiliation-labels#Organization affiliation labels#The bill page carries the notice once]] */}
            {supporting.length + opposing.length > 0 ? (
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    {PARITY_COPY.orgs.listNotice}
                </Text>
            ) : null}
            <StanceCard
                title={PARITY_COPY.bill.content.whySupport}
                emptyLabel={PARITY_COPY.org.noSupport}
                emptyTestID="org-positions-empty-support"
                stance="support"
                positions={supporting}
                newsTestimonies={newsTestimonies}
                onOpenUrl={onOpenUrl}
            />
            <StanceCard
                title={PARITY_COPY.bill.content.whyOppose}
                emptyLabel={PARITY_COPY.org.noOppose}
                emptyTestID="org-positions-empty-oppose"
                stance="oppose"
                positions={opposing}
                newsTestimonies={newsTestimonies}
                onOpenUrl={onOpenUrl}
            />
        </View>
    );
}
