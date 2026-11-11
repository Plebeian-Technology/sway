// @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]

export const INTENTIONAL_EMPTY_LIST_PARAMETERS = ["selected_stages", "stages"] as const;

export type IntentionalEmptyListParameter = (typeof INTENTIONAL_EMPTY_LIST_PARAMETERS)[number];

export const isIntentionalEmptyListParameter = (name: string): boolean => {
    return (INTENTIONAL_EMPTY_LIST_PARAMETERS as readonly string[]).includes(name);
};

export const addressWithEmptyList = (address: string, name: string): string => {
    const origin =
        typeof window !== "undefined" && window.location?.origin ? window.location.origin : "http://localhost";
    const url = new URL(address, origin);
    url.searchParams.delete(`${name}[]`);
    url.searchParams.set(name, "");
    return `${url.pathname}${url.search}`;
};
