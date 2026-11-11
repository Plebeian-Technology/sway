import React, { useMemo } from "react";
import type { IAdminBillNewsArticle, ISourceUseInput, NewsUsage } from "app/frontend/types/bill_creator";

export interface IManualNewsEvidenceControlsProps {
    summary: string;
    newsUsage: NewsUsage;
    onChangeNewsUsage: (usage: NewsUsage) => void;
    sourceUses?: ISourceUseInput[];
    onChangeSourceUses?: (sources: ISourceUseInput[]) => void;
    newsArticles?: IAdminBillNewsArticle[];
}

function hasExternalNewsUrls(prose: string): boolean {
    const urlMatches = prose.match(/https?:\/\/[^\s)]+/g) || [];
    const officialHosts = ["baltimore.legistar.com", "mgaleg.maryland.gov", "congress.gov", "localhost", "127.0.0.1"];
    for (const urlStr of urlMatches) {
        try {
            const parsed = new URL(urlStr);
            const isOfficial = officialHosts.some(
                (host) => parsed.hostname === host || parsed.hostname.endsWith(`.${host}`),
            );
            if (!isOfficial) {
                return true;
            }
        } catch {
            return true;
        }
    }
    return false;
}

// @lat: [[news-manual-evidence-ui#Manual evidence review controls]]
const ManualNewsEvidenceControls: React.FC<IManualNewsEvidenceControlsProps> = ({
    summary,
    newsUsage,
    onChangeNewsUsage,
}) => {
    const externalNewsLinksPresent = useMemo(() => {
        return hasExternalNewsUrls(summary);
    }, [summary]);

    return (
        <div className="flex flex-col gap-3 rounded-xl border-neo border-border-strong bg-surface-2 p-3 sm:p-4">
            <div className="flex flex-col gap-1">
                <span className="text-sm font-semibold text-foreground">News Evidence Usage</span>
                <span className="text-xs text-muted-foreground">
                    Declare whether this summary cites external reporting or relies exclusively on official materials.
                </span>
            </div>

            <div className="flex flex-wrap items-center gap-4 text-xs">
                <span className="flex items-center gap-1.5 cursor-pointer font-medium">
                    <input
                        type="radio"
                        id="news-usage-none"
                        name="news_usage"
                        value="none"
                        checked={newsUsage === "none"}
                        onChange={() => onChangeNewsUsage("none")}
                        data-testid="news-usage-none"
                        className="accent-primary"
                    />
                    <span>No news reporting cited (official materials only)</span>
                </span>

                <span className="flex items-center gap-1.5 cursor-pointer font-medium">
                    <input
                        type="radio"
                        id="news-usage-cited"
                        name="news_usage"
                        value="cited"
                        checked={newsUsage === "cited"}
                        onChange={() => onChangeNewsUsage("cited")}
                        data-testid="news-usage-cited"
                        className="accent-primary"
                    />
                    <span>Cite approved news reporting</span>
                </span>
            </div>

            {newsUsage === "none" && externalNewsLinksPresent && (
                <div
                    data-testid="news-usage-none-warning"
                    className="rounded-xl border-neo border-warning bg-warning/12 p-3 text-xs text-foreground flex flex-col gap-1"
                >
                    <span className="font-semibold">Notice: External links detected in summary prose</span>
                    <span>
                        Summary prose contains external links, but news usage is set to &quot;none&quot;. Please remove
                        external links or switch to cited mode, as external news citations require &quot;cited&quot;
                        mode.
                    </span>
                </div>
            )}
        </div>
    );
};

export default ManualNewsEvidenceControls;
