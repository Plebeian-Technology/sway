// @lat: [[mobile-org-membership-components-design#PositionCard]]
import React from "react";
import { Linking, Text, View } from "react-native";

import { Card, CardContent, CardFooter, CardHeader } from "./ui/Card";
import { Pressable } from "./ui/Pressable";
import { Markdown } from "./Markdown";
import { StampedBadge } from "./StampedBadge";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { billHeadline } from "../utils/billTitle";
import { isSafeCitationUrl } from "../utils/safeUrl";

export interface OrgPositionDisplay {
    id: number;
    support: string;
    summary: string | null;
    // @lat: [[mobile-org-membership-components-design#PositionCard]]
    summary_ai_unreviewed?: boolean;
    // @lat: [[news-org-position-persistence#Position origin and affiliation]]
    source_kind?: "hearing_testimony" | "news_article" | "sway_admin" | "organization" | null;
    source_url?: string | null;
    link?: string | null;
    bill?: {
        id?: number;
        external_id?: string;
        title?: string;
        headline?: string;
    } | null;
    bill_id?: number;
}

export interface PositionCardProps {
    position: OrgPositionDisplay;
    // @lat: [[organization-affiliation-labels#Organization affiliation labels#Every position carries its own tag]]
    organizationName?: string;
    testID?: string;
}

export function PositionCard({ position, organizationName, testID }: PositionCardProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const isSupport = position.support === "FOR";
    const badgeColor = isSupport ? t.voteFor : t.voteAgainst;
    const badgeLabel = isSupport ? PARITY_COPY.positions.supports : PARITY_COPY.positions.opposes;

    return (
        <Card testID={testID ?? `position-card-${position.id}`} className="mb-3">
            <CardHeader>
                {position.bill?.external_id ? (
                    <View className="bg-accent-light dark:bg-accent-dark px-2 py-1 rounded self-start">
                        <Text
                            className="text-xs font-open-sans-semibold text-accent-foreground-light dark:text-accent-foreground-dark"
                            style={{ textTransform: "uppercase", letterSpacing: 1.8 }}
                        >
                            {position.bill.external_id}
                        </Text>
                    </View>
                ) : null}
                <StampedBadge label={badgeLabel} color={badgeColor} />
                {organizationName !== undefined ? (
                    <Text
                        testID="org-position-source-tag"
                        className="text-xs font-open-sans-semibold uppercase text-muted-foreground-light dark:text-muted-foreground-dark"
                    >
                        {position.source_kind === "organization"
                            ? PARITY_COPY.orgs.postedBy(organizationName)
                            : PARITY_COPY.orgs.compiledBySway}
                    </Text>
                ) : null}
                {position.bill?.title ? (
                    <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {position.bill.headline ?? billHeadline(position.bill.title)}
                    </Text>
                ) : null}
            </CardHeader>
            <CardContent>
                {position.summary ? (
                    <Markdown
                        content={position.summary}
                        className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                    />
                ) : null}
                {position.summary_ai_unreviewed ? (
                    <Text
                        testID="ai-unreviewed-notice"
                        className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                    >
                        {PARITY_COPY.bill.aiUnreviewedNotice}
                    </Text>
                ) : null}
            </CardContent>
            {position.link && isSafeCitationUrl(position.link) ? (
                <CardFooter>
                    <Pressable
                        variant="ghost"
                        accessibilityRole="link"
                        accessibilityLabel="Open source URL"
                        onPress={() => {
                            if (position.link && isSafeCitationUrl(position.link)) {
                                void Linking.openURL(position.link).catch(() => {});
                            }
                        }}
                    >
                        <Text className="text-sm font-open-sans-semibold text-accent-light dark:text-accent-dark">
                            Source
                        </Text>
                    </Pressable>
                </CardFooter>
            ) : null}
        </Card>
    );
}

export default PositionCard;
