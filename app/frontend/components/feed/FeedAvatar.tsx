import { useState } from "react";

import type { IFeedLegislator } from "app/frontend/components/feed/types";

const LOCALE_ABBREVIATIONS: Record<string, string> = {
    "Baltimore City": "BAL",
    Maryland: "MD",
    "U.S. Congress": "US",
    Congress: "US",
};

const getLocaleAbbreviation = (localeName: string): string => {
    if (LOCALE_ABBREVIATIONS[localeName]) {
        return LOCALE_ABBREVIATIONS[localeName];
    }
    const words = localeName.trim().split(/\s+/);
    if (words.length >= 2) {
        return words
            .slice(0, 3)
            .map((w) => w[0]?.toUpperCase() ?? "")
            .join("");
    }
    return localeName.slice(0, 3).toUpperCase();
};

const getInitials = (name: string): string => {
    const parts = name.trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return "?";
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return `${parts[0][0] ?? ""}${parts[parts.length - 1][0] ?? ""}`.toUpperCase();
};

export const LocaleTile: React.FC<{ localeName: string }> = ({ localeName }) => (
    <div
        aria-hidden="true"
        className="flex size-11 items-center justify-center rounded-md bg-surface-3 text-xs font-bold tracking-wide text-primary"
    >
        {getLocaleAbbreviation(localeName)}
    </div>
);

export const LegislatorAvatar: React.FC<{ legislator: IFeedLegislator }> = ({ legislator }) => {
    const [failedUrl, setFailedUrl] = useState<string | null>(null);
    const showImage = Boolean(legislator.photo_url) && failedUrl !== legislator.photo_url;

    if (showImage && legislator.photo_url) {
        return (
            <img
                src={legislator.photo_url}
                alt={legislator.full_name}
                onError={() => setFailedUrl(legislator.photo_url)}
                className="size-11 rounded-full border border-border bg-surface-2 object-cover"
            />
        );
    }

    return (
        <div
            aria-hidden="true"
            className="flex size-11 items-center justify-center rounded-full bg-surface-2 text-sm font-semibold text-muted-foreground"
        >
            {getInitials(legislator.full_name)}
        </div>
    );
};

export const OrganizationTile: React.FC<{ name: string }> = ({ name }) => (
    <div
        aria-hidden="true"
        className="flex size-11 items-center justify-center rounded-md bg-surface-2 text-xs font-bold text-foreground"
    >
        {getInitials(name)}
    </div>
);
