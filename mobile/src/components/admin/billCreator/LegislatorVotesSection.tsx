// @lat: [[mobile-bill-creator#Sections#The legislator votes section]]
import React, { useMemo, useState } from "react";
import { Text, View } from "react-native";

import { Routes } from "../../../api/routes";
import { Pressable } from "../../ui/Pressable";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { CreatorLegislator } from "./BillFieldsSection";

export interface CreatorVoteLegislator extends CreatorLegislator {
    active?: boolean;
}

export interface CreatorLegislatorVote {
    legislator_id: number;
    support: string | null;
}

type Support = "FOR" | "AGAINST" | "ABSTAIN";

const SUPPORT_COLUMNS: { key: Support; label: string }[] = [
    { key: "FOR", label: "For" },
    { key: "AGAINST", label: "Against" },
    { key: "ABSTAIN", label: "Abstain" },
];

const NO_LEGISLATORS_MESSAGE = "No legislators available for this locale yet.";
const UNSAVED_BILL_MESSAGE = "Save the bill before saving votes.";
const REFUSAL_FALLBACK = "Could not save legislator votes.";
const ONE_POSITION_NOTE = "A legislator holds one position on a bill, so picking one of these clears the other two.";

const titleize = (text: string) =>
    text
        .toLowerCase()
        .split(" ")
        .filter(Boolean)
        .map((word) => word[0].toUpperCase() + word.slice(1))
        .join(" ");

const displayName = (legislator: CreatorLegislator) =>
    `${titleize(legislator.first_name)} ${titleize(legislator.last_name)}`;

const isSupport = (support: string | null): support is Support =>
    SUPPORT_COLUMNS.some((column) => column.key === support);

const nonBlank = (text: unknown): string | undefined =>
    typeof text === "string" && text.trim().length > 0 ? text : undefined;

interface LegislatorVotesSectionProps {
    billId: number | null;
    legislators: CreatorVoteLegislator[];
    legislatorVotes: CreatorLegislatorVote[];
    refreshedAt: string | null;
    source: string | null;
}

export default function LegislatorVotesSection({
    billId,
    legislators,
    legislatorVotes,
    refreshedAt,
    source,
}: LegislatorVotesSectionProps) {
    const [supportByLegislator, setSupportByLegislator] = useState<Map<number, Support>>(
        () =>
            new Map(
                legislatorVotes.flatMap((vote): [number, Support][] =>
                    isSupport(vote.support) ? [[vote.legislator_id, vote.support]] : [],
                ),
            ),
    );
    const [formMessage, setFormMessage] = useState<string | null>(null);
    const [saved, setSaved] = useState(false);
    const { run, loading, errorMessage, fieldErrors } = useAdminMutation<unknown>(
        "post",
        Routes.adminLegislatorVotes(),
    );

    const sortedLegislators = useMemo(
        () =>
            legislators
                .map((legislator) => ({ legislator, name: displayName(legislator) }))
                .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase())),
        [legislators],
    );

    const selectSupport = (legislatorId: number, support: Support) => {
        setSaved(false);
        setSupportByLegislator((current) => {
            const next = new Map(current);
            next.delete(legislatorId);
            next.set(legislatorId, support);
            return next;
        });
    };

    const save = async () => {
        setSaved(false);
        if (billId === null) {
            setFormMessage(UNSAVED_BILL_MESSAGE);
            return;
        }
        setFormMessage(null);
        const payload = SUPPORT_COLUMNS.flatMap(({ key }) =>
            [...supportByLegislator]
                .filter(([, support]) => support === key)
                .map(([legislator_id, support]) => ({ legislator_id, support })),
        );
        const response = await run({ bill_id: billId, legislator_votes: payload });
        if (response !== undefined) setSaved(true);
    };

    if (sortedLegislators.length === 0) {
        return (
            <View testID="admin-legislator-votes" className="px-4">
                <Text className="py-6 text-sm italic font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                    {NO_LEGISLATORS_MESSAGE}
                </Text>
            </View>
        );
    }

    const refusal =
        errorMessage === null
            ? undefined
            : (nonBlank(fieldErrors?.legislator_votes) ?? nonBlank(errorMessage) ?? REFUSAL_FALLBACK);
    const shownError = formMessage ?? refusal;

    return (
        <View testID="admin-legislator-votes" className="px-4">
            <Text className="mb-2 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                Legislator Votes
            </Text>
            <Text className="mb-3 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                {ONE_POSITION_NOTE}
            </Text>
            {refreshedAt && source ? (
                <Text
                    testID="admin-legislator-votes-refreshed"
                    className="mb-3 text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark"
                >
                    {`Legislator votes refreshed at ${refreshedAt} from ${source}.`}
                </Text>
            ) : null}
            {sortedLegislators.map(({ legislator, name }) => (
                <View key={legislator.id} testID={`admin-legislator-votes-row-${legislator.id}`} className="mb-4">
                    <View className="flex-row items-center">
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {name}
                        </Text>
                        {legislator.active === false ? (
                            <Text
                                testID={`admin-legislator-votes-former-${legislator.id}`}
                                className="ml-2 text-xs font-open-sans-semibold uppercase text-muted-foreground-light dark:text-muted-foreground-dark"
                            >
                                Former
                            </Text>
                        ) : null}
                    </View>
                    {legislator.district ? (
                        <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            {`${legislator.district.region_code} · District ${legislator.district.number}`}
                        </Text>
                    ) : null}
                    <View
                        accessibilityRole="radiogroup"
                        accessibilityLabel={`${name} vote`}
                        className="mt-2 flex-row gap-2"
                    >
                        {SUPPORT_COLUMNS.map(({ key, label }) => {
                            const selected = supportByLegislator.get(legislator.id) === key;
                            return (
                                <View key={key} className="flex-1">
                                    <Pressable
                                        testID={`admin-legislator-votes-${legislator.id}-${key}`}
                                        variant={selected ? "default" : "outline"}
                                        disabled={loading}
                                        accessibilityRole="radio"
                                        accessibilityLabel={`${label} for ${name}`}
                                        accessibilityState={{ checked: selected }}
                                        onPress={() => selectSupport(legislator.id, key)}
                                    >
                                        <Text
                                            className={
                                                selected
                                                    ? "text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark"
                                                    : "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                                            }
                                        >
                                            {label}
                                        </Text>
                                    </Pressable>
                                </View>
                            );
                        })}
                    </View>
                </View>
            ))}
            {shownError ? (
                <Text
                    testID="admin-legislator-votes-error"
                    className="mb-3 text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark"
                >
                    {shownError}
                </Text>
            ) : null}
            {saved ? (
                <Text
                    testID="admin-legislator-votes-saved"
                    className="mb-3 text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
                >
                    Legislator votes saved.
                </Text>
            ) : null}
            <Pressable
                testID="admin-legislator-votes-save"
                variant="default"
                disabled={loading}
                accessibilityLabel="Save legislator votes"
                onPress={() => void save()}
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {loading ? "Saving..." : "Save Legislator Votes"}
                </Text>
            </Pressable>
        </View>
    );
}
