// @lat: [[mobile-bill-creator#Sections#The pipeline read-only panels]]
import React from "react";
import { Text, View } from "react-native";

import { parseTime, relativeTime } from "../../../utils/runTime";
import CollapsibleSection from "./CollapsibleSection";

export type ResourceCacheTier = "pdf" | "extracted_text" | "parsed_sections" | "diff" | "summary";

export interface ResourceCacheRow {
    tier: ResourceCacheTier;
    last_generated_at: string;
    version_id: string | null;
    stale: boolean;
    source_artifact_id: string | null;
}

interface ResourceCacheSectionProps {
    mirrors: ResourceCacheRow[];
}

const TIERS: { tier: ResourceCacheTier; label: string }[] = [
    { tier: "pdf", label: "PDF" },
    { tier: "extracted_text", label: "Extracted Text" },
    { tier: "parsed_sections", label: "Parsed Sections" },
    { tier: "diff", label: "Diff" },
    { tier: "summary", label: "Summary" },
];

const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";
const mutedText = "text-xs font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark";
const staleText = "text-xs font-open-sans-semibold text-warning-foreground-light dark:text-warning-foreground-dark";

const generatedAgo = (iso: string) => {
    const date = parseTime(iso);
    return date ? relativeTime(date) : "—";
};

const ResourceCacheSection: React.FC<ResourceCacheSectionProps> = ({ mirrors }) => (
    <CollapsibleSection testID="admin-resource-cache" title="Resource cache">
        {TIERS.map(({ tier, label }) => {
            const mirror = mirrors.find((row) => row.tier === tier);
            return (
                <View
                    key={tier}
                    testID={`admin-resource-cache-tier-${tier}`}
                    className="rounded-lg border border-border-soft-light dark:border-border-soft-dark p-3 gap-1"
                >
                    <Text className={mirror ? labelText : mutedText}>{label}</Text>
                    {mirror ? (
                        <>
                            <Text className={mutedText}>Last generated {generatedAgo(mirror.last_generated_at)}</Text>
                            <Text className={mutedText}>Version {mirror.version_id ?? "—"}</Text>
                            <Text className={mirror.stale ? staleText : mutedText}>
                                {mirror.stale ? "Stale" : "Fresh"}
                            </Text>
                        </>
                    ) : (
                        <>
                            <Text className={mutedText}>Last generated —</Text>
                            <Text className={mutedText}>Version —</Text>
                            <Text className={mutedText}>Not cached</Text>
                        </>
                    )}
                </View>
            );
        })}
    </CollapsibleSection>
);

export default ResourceCacheSection;
