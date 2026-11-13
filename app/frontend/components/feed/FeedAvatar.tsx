import { useState } from "react";

import { getInitials, getLocaleAbbreviation } from "app/frontend/components/feed/avatarText";
import type { IFeedLegislator } from "app/frontend/components/feed/types";

interface IProps {
    kind: "locale" | "legislator" | "organization";
    localeName?: string;
    legislator?: IFeedLegislator;
    organizationName?: string;
}

const FeedAvatar: React.FC<IProps> = ({ kind, localeName = "", legislator, organizationName = "" }) => {
    const [failedUrl, setFailedUrl] = useState<string | null>(null);

    if (kind === "locale") {
        return (
            <div
                aria-hidden="true"
                className="flex size-11 items-center justify-center rounded-md bg-surface-3 text-xs font-bold tracking-wide text-primary"
            >
                {getLocaleAbbreviation(localeName)}
            </div>
        );
    }

    if (kind === "organization") {
        return (
            <div
                aria-hidden="true"
                className="flex size-11 items-center justify-center rounded-md bg-surface-2 text-xs font-bold text-foreground"
            >
                {getInitials(organizationName)}
            </div>
        );
    }

    const fullName = legislator?.full_name ?? "";
    const photoUrl = legislator?.photo_url ?? null;
    const showImage = Boolean(photoUrl) && failedUrl !== photoUrl;

    if (showImage && photoUrl) {
        return (
            <img
                src={photoUrl}
                alt={fullName}
                onError={() => setFailedUrl(photoUrl)}
                className="size-11 rounded-full border border-border bg-surface-2 object-cover"
            />
        );
    }

    return (
        <div
            aria-hidden="true"
            className="flex size-11 items-center justify-center rounded-full bg-surface-2 text-sm font-semibold text-muted-foreground"
        >
            {getInitials(fullName)}
        </div>
    );
};

export default FeedAvatar;
