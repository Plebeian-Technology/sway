// @lat: [[unlinked-bill-presentation#Separation of URL safety from link validity]]
// @lat: [[unlinked-bill-presentation#Cross-platform parity in unlinked presentation]]
import React from "react";
import { Text, View } from "react-native";
import { ExternalLink, Share2 } from "lucide-react-native";
import { Card, CardContent, CardHeader, CardTitle } from "./ui/Card";
import { Pressable } from "./ui/Pressable";
import { useShareBill } from "../hooks/useShareBill";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

import { isOnOfficialSourceHost, openSourceLink } from "../utils/officialSourceLink";

// @lat: [[mobile-bill-surface-components-design#HearingTestimonySection#LOCALE_LINK_LABELS]]
const LOCALE_LINK_LABELS: Record<string, string> = {
    "baltimore-maryland-united_states": "Baltimore Legistar",
    "baltimore_county-maryland-united_states": "Baltimore County Website",
    "los_angeles-california-united_states": "LACityClerk Connect",
    "washington-district_of_columbia-united_states": "Washington DC LIMS",
    "maryland-maryland-united_states": "mgaleg.maryland.gov",
    "congress-congress-united_states": "congress.gov",
};

// @lat: [[unlinked-bill-presentation#Separation of URL safety from link validity]]
export function hasValidSourceLink(link?: string | null, genericPortalUrls?: string[]): boolean {
    if (!link || typeof link !== "string" || link.trim() === "") return false;

    try {
        const parsed = new URL(link.trim());
        if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return false;

        const hostname = parsed.hostname.toLowerCase();
        const pathname = parsed.pathname.toLowerCase().replace(/\/+$/, "");

        if (genericPortalUrls && genericPortalUrls.length > 0) {
            for (const portalUrl of genericPortalUrls) {
                if (!portalUrl || typeof portalUrl !== "string") continue;
                try {
                    const portal = new URL(portalUrl.trim());
                    const portalHost = portal.hostname.toLowerCase();
                    const portalPath = portal.pathname.toLowerCase().replace(/\/+$/, "");
                    if (hostname === portalHost && pathname === portalPath) {
                        return false;
                    }
                } catch {}
            }
        }

        return true;
    } catch {
        return false;
    }
}

export interface SourceLinkPolicy {
    genericPortalUrls?: string[];
    swayLocaleSlug?: string;
    allowedSourceHosts?: readonly string[];
}

// @lat: [[unlinked-bill-presentation#Separation of URL safety from link validity]]
export function canOpenSourceLink(link: string | null | undefined, policy: SourceLinkPolicy = {}): boolean {
    return (
        hasValidSourceLink(link, policy.genericPortalUrls) &&
        isOnOfficialSourceHost(link, policy.swayLocaleSlug, policy.allowedSourceHosts)
    );
}

export interface HearingTestimonySectionBill {
    id?: number;
    title?: string;
    link?: string | null;
}

export interface HearingTestimonySectionProps {
    bill: HearingTestimonySectionBill;
    userVote?: { support?: string | null } | null;
    swayLocaleSlug?: string;
    allowedSourceHosts?: readonly string[];
    genericPortalUrls?: string[];
    testID?: string;
    // @lat: [[mobile-bill-surface-components-design#HearingTestimonySection#onNavigateToLegislators / onNavigateToBills props]]
    onNavigateToLegislators?: () => void;
    onNavigateToBills?: () => void;
    onShareBill?: () => void;
}

export function HearingTestimonySection({
    bill,
    userVote,
    swayLocaleSlug,
    allowedSourceHosts,
    genericPortalUrls,
    testID,
    onNavigateToLegislators,
    onNavigateToBills,
    onShareBill,
}: HearingTestimonySectionProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const { shareBill } = useShareBill();

    const handleShareBill = () => {
        if (onShareBill) {
            onShareBill();
        } else {
            void shareBill(bill);
        }
    };

    const customSiteLabel = swayLocaleSlug ? LOCALE_LINK_LABELS[swayLocaleSlug] : undefined;
    const linkLabel = customSiteLabel ? `View on ${customSiteLabel}` : "Open bill on government website";

    const canOpenBill = canOpenSourceLink(bill.link, { genericPortalUrls, swayLocaleSlug, allowedSourceHosts });

    const handleOpenBill = () => {
        if (!canOpenBill) return;
        openSourceLink(bill.link as string);
    };

    return (
        <Card testID={testID ?? "legislator-comparison"}>
            <CardHeader>
                <CardTitle>{PARITY_COPY.bill.content.takeNextStep}</CardTitle>
            </CardHeader>
            <CardContent className="gap-3">
                {userVote ? (
                    <>
                        <Pressable
                            variant="outline"
                            onPress={onNavigateToLegislators ?? (() => {})}
                            accessibilityRole="button"
                            accessibilityLabel="Compare your vote with your representatives"
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {PARITY_COPY.bill.compareWithReps}
                            </Text>
                        </Pressable>
                        <Pressable
                            variant="outline"
                            onPress={onNavigateToBills ?? (() => {})}
                            accessibilityRole="button"
                            accessibilityLabel="Vote on past legislation"
                        >
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {PARITY_COPY.bill.voteOnPastLegislation}
                            </Text>
                        </Pressable>
                    </>
                ) : null}

                {bill.id != null ? (
                    <Pressable
                        testID="share-bill-button"
                        variant="outline"
                        onPress={handleShareBill}
                        accessibilityRole="button"
                        accessibilityLabel={PARITY_COPY.bill.shareBill}
                    >
                        <View className="flex-row items-center gap-2">
                            <Share2 size={16} color={t.foreground} />
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {PARITY_COPY.bill.shareBill}
                            </Text>
                        </View>
                    </Pressable>
                ) : null}

                {canOpenBill ? (
                    <Pressable
                        testID="open-bill-link"
                        variant="default"
                        onPress={handleOpenBill}
                        accessibilityRole="link"
                        accessibilityLabel={linkLabel}
                        accessibilityHint="Opens an external website in your browser"
                    >
                        <View className="flex-row items-center justify-center gap-2">
                            <Text className="shrink text-center text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                {linkLabel}
                            </Text>
                            <ExternalLink size={16} color={t.primaryForeground} />
                        </View>
                    </Pressable>
                ) : (
                    <Text
                        testID="no-source-link"
                        className="text-xs font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark"
                    >
                        {PARITY_COPY.bill.officialSourceUnavailable}
                    </Text>
                )}
            </CardContent>
        </Card>
    );
}
