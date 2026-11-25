// @lat: [[mobile-bill-creator#Sections#The testimony section#Overriding a letter's stance]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { PARITY_COPY } from "../../../../../app/frontend/sway_constants/parityCopy";
import { Routes } from "../../../api/routes";
import { useAdminMutation } from "../../../hooks/admin/useAdminMutation";
import type { BillCreatorTabProps } from "../../../hooks/admin/useBillCreator";
import { usePublicTestimonyLetters } from "../../../hooks/usePublicTestimony";
import type { PublicTestimonyCounts, PublicTestimonyStance } from "../../../types/bill";
import { BrowseTestimonySheet } from "../../BrowseTestimonySheet";
import { Pressable } from "../../ui/Pressable";

const COPY = PARITY_COPY.publicTestimony.section;

const refusalOf = (errorMessage: string | null, fieldErrors: Record<string, unknown> | null) => {
    if (errorMessage === null) return null;
    const reason = fieldErrors?.testimony_letter_stance;
    return typeof reason === "string" && reason.trim() !== "" ? reason : errorMessage;
};

const TestimonyLettersSection: React.FC<BillCreatorTabProps> = ({ billId, data, refresh }) => {
    const [open, setOpen] = useState(false);
    const counts = (data.public_testimony_counts ?? null) as PublicTestimonyCounts | null;
    const shown = billId !== null && counts !== null && counts.total > 0;
    const {
        letters,
        error,
        refresh: refreshLetters,
    } = usePublicTestimonyLetters(billId ?? 0, {
        enabled: shown && open,
    });
    const stanceWrite = useAdminMutation<unknown>("patch", Routes.billTestimonyLetterStance(billId ?? 0));

    if (!shown && open) setOpen(false);
    if (!shown || counts === null) return null;

    const write = async (body: { position: number; stance?: PublicTestimonyStance; excluded?: boolean }) => {
        const response = await stanceWrite.run(body);
        if (response !== undefined) await Promise.all([refreshLetters(), refresh()]);
    };

    return (
        <View testID="admin-testimony-letters" className="px-4 mt-6 gap-3">
            <Text
                accessibilityRole="header"
                className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark"
            >
                {COPY.heading}
            </Text>
            <Text className="text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                {COPY.subtitle(counts.total)}
            </Text>
            <Pressable
                testID="admin-testimony-letters-browse"
                variant="outline"
                onPress={() => setOpen(true)}
                accessibilityLabel={COPY.browseButton}
            >
                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                    {COPY.browseButton}
                </Text>
            </Pressable>
            <BrowseTestimonySheet
                visible={open}
                onClose={() => setOpen(false)}
                counts={counts}
                letters={letters}
                error={error}
                onRetry={() => void refreshLetters()}
                billTitle={(data.bill as { title?: string } | undefined)?.title}
                letterEditing={{
                    onSetStance: (position, stance) => void write({ position, stance }),
                    onRemove: (position) => void write({ position, excluded: true }),
                    busy: stanceWrite.loading,
                    error: refusalOf(stanceWrite.errorMessage, stanceWrite.fieldErrors),
                }}
            />
        </View>
    );
};

export default TestimonyLettersSection;
