import { sway } from "sway";

// @lat: [[system-shape#Deployment#The logo tooltip includes the running build]]
export const formatDeployedAt = (iso: string | null | undefined): string => {
    if (!iso) return "—";

    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return "—";

    return new Intl.DateTimeFormat(undefined, {
        dateStyle: "medium",
        timeStyle: "short",
    }).format(date);
};

export const releaseLabel = (release: sway.IRelease | null | undefined): string =>
    !release || release.version === null ? "Development build" : `Release #${release.version}`;
