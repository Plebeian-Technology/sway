// @lat: [[mobile-bill-surface-components-design#BrowseTestimonySheet]]
import React, { useRef, useState } from "react";
import { Modal, Platform, Pressable as RNPressable, ScrollView, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import type { PublicTestimonyCounts, PublicTestimonyLetter, PublicTestimonyStance } from "../types/bill";
import { StampedBadge, readableForeground } from "./StampedBadge";
import { SkeletonCard } from "./SkeletonCard";
import { EmptyState } from "./ui/EmptyState";
import { Pressable } from "./ui/Pressable";

export type TStanceFilter = "all" | PublicTestimonyStance;

export interface BrowseTestimonySheetProps {
    visible: boolean;
    onClose: () => void;
    counts: PublicTestimonyCounts;
    letters: PublicTestimonyLetter[] | null;
    error: Error | null;
    onRetry: () => void;
    initialFilter?: TStanceFilter;
    billTitle?: string;
    testID?: string;
}

const PAGE_SIZE = 10;
const COPY = PARITY_COPY.publicTestimony.modal;

const TABS: { key: TStanceFilter; label: string; count: (counts: PublicTestimonyCounts) => number }[] = [
    { key: "all", label: COPY.allTab, count: (counts) => counts.total },
    { key: "support", label: COPY.supportTab, count: (counts) => counts.support },
    { key: "oppose", label: COPY.opposeTab, count: (counts) => counts.oppose },
    { key: "neutral", label: COPY.neutralTab, count: (counts) => counts.neutral },
];

const STANCE_BADGE_LABEL: Record<PublicTestimonyStance, string> = {
    support: COPY.supportBadge,
    oppose: COPY.opposeBadge,
    neutral: COPY.neutralBadge,
};

export function BrowseTestimonySheet(props: BrowseTestimonySheetProps) {
    if (!props.visible) return null;
    return <BrowseTestimonyModal {...props} />;
}

function BrowseTestimonyModal({
    onClose,
    counts,
    letters,
    error,
    onRetry,
    initialFilter = "all",
    billTitle,
    testID,
}: BrowseTestimonySheetProps) {
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];
    const rootTestID = testID ?? "browse-testimony-sheet";
    const scrollRef = useRef<ScrollView>(null);
    const [activeTab, setActiveTab] = useState<TStanceFilter>(initialFilter);
    const [visibleCount, setVisibleCount] = useState(PAGE_SIZE);

    const stanceColor: Record<PublicTestimonyStance, string> = {
        support: t.success,
        oppose: t.destructive,
        neutral: t.mutedForeground,
    };

    const selectTab = (key: TStanceFilter) => {
        setActiveTab(key);
        setVisibleCount(PAGE_SIZE);
        scrollRef.current?.scrollTo({ y: 0, animated: false });
    };

    const filtered =
        letters === null ? [] : activeTab === "all" ? letters : letters.filter((l) => l.stance === activeTab);
    const shown = filtered.slice(0, visibleCount);
    const remaining = filtered.length - shown.length;

    const renderBody = () => {
        if (letters === null && error) {
            return (
                <View testID={`${rootTestID}-error`} accessibilityRole="alert">
                    <EmptyState
                        title={COPY.loadError}
                        ctaLabel={PARITY_COPY.legislators.historyRetry}
                        onCtaPress={onRetry}
                    />
                </View>
            );
        }
        if (letters === null) {
            return (
                <View
                    testID={`${rootTestID}-loading`}
                    accessibilityLiveRegion="polite"
                    accessibilityLabel={COPY.loading}
                    className="gap-3"
                >
                    <SkeletonCard heightClass="h-28" testID={`${rootTestID}-loading-1`} />
                    <SkeletonCard heightClass="h-28" testID={`${rootTestID}-loading-2`} />
                    <SkeletonCard heightClass="h-28" testID={`${rootTestID}-loading-3`} />
                    <Text className="text-center text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                        {COPY.loading}
                    </Text>
                </View>
            );
        }
        if (filtered.length === 0) {
            return <EmptyState title={COPY.empty} testID={`${rootTestID}-empty`} />;
        }
        return (
            <>
                {shown.map((letter) => (
                    <View
                        key={`${letter.position}-${letter.label}`}
                        testID={`testimony-letter-${letter.position}`}
                        className="gap-2 rounded-card border border-border-soft-light bg-card-light px-4 py-4 dark:border-border-soft-dark dark:bg-card-dark"
                    >
                        <View className="flex-row flex-wrap items-center justify-between gap-2">
                            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                {letter.label}
                            </Text>
                            <StampedBadge
                                label={STANCE_BADGE_LABEL[letter.stance]}
                                color={stanceColor[letter.stance]}
                                accessibilityPrefix={PARITY_COPY.publicTestimony.modal.stancePrefix}
                                testID={`testimony-letter-${letter.position}-stance`}
                            />
                        </View>
                        <Text
                            selectable
                            className="text-base font-open-sans text-foreground-light dark:text-foreground-dark"
                        >
                            {letter.body_text}
                        </Text>
                    </View>
                ))}
                {remaining > 0 ? (
                    <Pressable
                        testID={`${rootTestID}-more`}
                        variant="outline"
                        onPress={() => setVisibleCount((count) => count + PAGE_SIZE)}
                        accessibilityLabel={`${PARITY_COPY.bill.showMore}, ${remaining} remaining`}
                    >
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {PARITY_COPY.bill.showMore}
                        </Text>
                    </Pressable>
                ) : null}
            </>
        );
    };

    return (
        <Modal
            testID={rootTestID}
            visible
            animationType="slide"
            presentationStyle={Platform.OS === "ios" ? "pageSheet" : undefined}
            allowSwipeDismissal
            onRequestClose={onClose}
        >
            <SafeAreaView className="flex-1 bg-dominant-light dark:bg-dominant-dark">
                <View className="flex-row items-start justify-between gap-2 border-b border-border-light px-4 py-3 dark:border-border-dark">
                    <View className="flex-1 gap-1">
                        <Text
                            accessibilityRole="header"
                            className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                        >
                            {COPY.title}
                        </Text>
                        {billTitle ? (
                            <Text
                                numberOfLines={1}
                                className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark"
                            >
                                {billTitle}
                            </Text>
                        ) : null}
                        <Text className="text-sm font-open-sans text-muted-foreground-light dark:text-muted-foreground-dark">
                            {COPY.subtitle(counts.total)}
                        </Text>
                    </View>
                    <Pressable
                        testID={`${rootTestID}-close`}
                        variant="ghost"
                        onPress={onClose}
                        accessibilityLabel={PARITY_COPY.publicTestimony.modal.close}
                    >
                        <Text className="text-base font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {PARITY_COPY.publicTestimony.modal.close}
                        </Text>
                    </Pressable>
                </View>

                <View
                    accessibilityRole="tablist"
                    className="mx-4 mt-3 flex-row gap-1 rounded-xl border border-accent-light bg-surface-3-light p-1 dark:border-accent-dark dark:bg-surface-3-dark"
                >
                    {TABS.map((tab) => {
                        const selected = tab.key === activeTab;
                        const count = tab.count(counts);
                        const foreground = selected ? readableForeground(t.accent) : t.foreground;
                        return (
                            <RNPressable
                                key={tab.key}
                                testID={`${rootTestID}-tab-${tab.key}`}
                                accessibilityRole="tab"
                                accessibilityState={{ selected }}
                                accessibilityLabel={`${tab.label} (${count})`}
                                onPress={() => selectTab(tab.key)}
                                className={`flex-1 items-center justify-center rounded-lg px-1 ${
                                    selected ? "bg-accent-light dark:bg-accent-dark" : "bg-transparent"
                                }`}
                                style={{ minHeight: 44 }}
                            >
                                <Text
                                    numberOfLines={1}
                                    className="text-sm font-open-sans-semibold"
                                    style={{ color: foreground }}
                                >
                                    {tab.label}
                                </Text>
                                <Text
                                    className="text-xs font-open-sans"
                                    style={{ color: foreground, fontVariant: ["tabular-nums"] }}
                                >
                                    {count}
                                </Text>
                            </RNPressable>
                        );
                    })}
                </View>

                <ScrollView
                    ref={scrollRef}
                    testID={`${rootTestID}-list`}
                    contentContainerStyle={{ padding: 16, gap: 12, paddingBottom: 32 }}
                >
                    {renderBody()}
                </ScrollView>
            </SafeAreaView>
        </Modal>
    );
}

export default BrowseTestimonySheet;
