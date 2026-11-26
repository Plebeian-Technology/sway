// @lat: [[query-parameter-namespaces#Decided prefix namespaces]]
// @lat: [[query-parameter-namespaces#Machine-readable registry and lint enforcement]]

export const GLOBAL_AMBIENT_QUERY_PARAMETERS = ["sway_locale_id", "run_id", "highlight_bill_id"] as const;

export type GlobalAmbientQueryParameter = (typeof GLOBAL_AMBIENT_QUERY_PARAMETERS)[number];

const FEATURE_DEFINITIONS = {
    bill_creator: {
        parameters: [
            "bill_creator_tab",
            "bill_creator_sort",
            "selected_stages",
            "download_missing_assets",
            "subject",
            "severity",
            "window",
            "cursor",
            "date",
            "highlight",
        ],
        route_patterns: ["^/admin/bill_creator", "^/bills/new", "^/bills/\\d+/edit"],
        parameter_families: {
            bill_creator_tab: ["tab_key"],
            bill_creator_sort: [],
            selected_stages: ["stages"],
            download_missing_assets: [],
            subject: [],
            severity: [],
            window: [],
            cursor: [],
            date: [],
            highlight: [],
        },
    },
    bills: {
        parameters: ["bills_sort", "bills_direction", "bills_page", "bills_search", "bills_legislative_session_id"],
        route_patterns: ["^/bills(?!/(new|\\d+/edit))", "^/past_bills_of_the_month"],
        parameter_families: {
            bills_sort: ["sort"],
            bills_direction: ["direction"],
            bills_page: ["page"],
            bills_search: ["search"],
            bills_legislative_session_id: ["legislative_session_id"],
        },
    },
    legislators: {
        parameters: ["legislators_tab", "legislators_search"],
        route_patterns: ["^/legislators"],
        parameter_families: {
            legislators_tab: ["tab"],
            legislators_search: ["search"],
        },
    },
    notifications: {
        parameters: ["notifications_tab"],
        route_patterns: ["^/notifications"],
        parameter_families: {
            notifications_tab: ["tab"],
        },
    },
    organizations: {
        parameters: ["org_tab", "org_search"],
        route_patterns: ["^/organizations", "^/public/organizations"],
        parameter_families: {
            org_tab: ["tab", "tab_key"],
            org_search: ["search"],
        },
    },
    feed: {
        parameters: ["feed_search", "feed_cursor"],
        route_patterns: ["^/feed"],
        parameter_families: {
            feed_search: [],
            feed_cursor: [],
        },
    },
} as const;

export type FeatureName = keyof typeof FEATURE_DEFINITIONS;

type TFeatureQueryParameters = {
    [Feature in FeatureName]: {
        parameters: (typeof FEATURE_DEFINITIONS)[Feature]["parameters"];
        legacy_aliases: string[];
        routePatterns: RegExp[];
    };
};

export const FEATURE_QUERY_PARAMETERS = Object.fromEntries(
    Object.entries(FEATURE_DEFINITIONS).map(([feature, definition]) => [
        feature,
        {
            parameters: definition.parameters,
            legacy_aliases: Object.values(definition.parameter_families).flat(),
            routePatterns: definition.route_patterns.map((pattern) => new RegExp(pattern)),
        },
    ]),
) as TFeatureQueryParameters;

export const FEATURE_ALIAS_MAP = Object.fromEntries(
    Object.entries(FEATURE_DEFINITIONS).map(([feature, definition]) => [
        feature,
        Object.fromEntries(Object.entries(definition.parameter_families).filter(([, aliases]) => aliases.length > 0)),
    ]),
) as Record<FeatureName, Record<string, readonly string[]>>;

export const QUERY_PARAMETER_REGISTRY_FOR_PARITY: {
    global_ambient: string[];
    features: Record<
        FeatureName,
        {
            parameters: string[];
            route_patterns: string[];
            parameter_families: Record<string, string[]>;
        }
    >;
} = {
    global_ambient: [...GLOBAL_AMBIENT_QUERY_PARAMETERS],
    features: Object.fromEntries(
        Object.entries(FEATURE_DEFINITIONS).map(([name, definition]) => [
            name,
            {
                parameters: [...definition.parameters],
                route_patterns: [...definition.route_patterns],
                parameter_families: Object.fromEntries(
                    Object.entries(definition.parameter_families).map(([canonical, aliases]) => [
                        canonical,
                        [...aliases],
                    ]),
                ),
            },
        ]),
    ) as Record<
        FeatureName,
        {
            parameters: string[];
            route_patterns: string[];
            parameter_families: Record<string, string[]>;
        }
    >,
};

export const getFeatureForPath = (pathname: string): FeatureName | null => {
    if (!pathname || typeof pathname !== "string") return null;
    const cleanPath = pathname.split("?")[0].split("#")[0];
    const matchingFeatures: FeatureName[] = [];
    for (const [featureName, config] of Object.entries(FEATURE_QUERY_PARAMETERS) as [
        FeatureName,
        (typeof FEATURE_QUERY_PARAMETERS)[FeatureName],
    ][]) {
        if (config.routePatterns.some((pattern) => pattern.test(cleanPath))) {
            matchingFeatures.push(featureName);
        }
    }
    return matchingFeatures.length === 1 ? matchingFeatures[0] : null;
};

export const isGlobalAmbientParameter = (name: string): boolean => {
    const base = name.replace(/\[\]$/, "");
    return (GLOBAL_AMBIENT_QUERY_PARAMETERS as readonly string[]).includes(base);
};

export function getParameterFamily(name: string, feature?: FeatureName | null): string[];
export function getParameterFamily(feature: FeatureName, name: string): string[];
export function getParameterFamily(arg1: string, arg2?: string | null): string[] {
    let name: string;
    let feature: FeatureName | null = null;

    if (arg1 in FEATURE_QUERY_PARAMETERS && typeof arg2 === "string" && !(arg2 in FEATURE_QUERY_PARAMETERS)) {
        feature = arg1 as FeatureName;
        name = arg2;
    } else {
        name = arg1;
        feature = (arg2 as FeatureName | null) ?? null;
    }

    const base = name.replace(/\[\]$/, "");

    if (!feature) {
        for (const [feat, config] of Object.entries(FEATURE_QUERY_PARAMETERS) as [
            FeatureName,
            (typeof FEATURE_QUERY_PARAMETERS)[FeatureName],
        ][]) {
            if ((config.parameters as readonly string[]).includes(base)) {
                feature = feat;
                break;
            }
        }
    }

    if (!feature || !(feature in FEATURE_ALIAS_MAP)) {
        return [base];
    }

    const featureAliases = FEATURE_ALIAS_MAP[feature] as Record<string, readonly string[]>;

    if (base in featureAliases) {
        return [base, ...featureAliases[base]];
    }

    for (const [canonical, aliases] of Object.entries(featureAliases)) {
        if ((aliases as readonly string[]).includes(base)) {
            return [canonical, ...aliases];
        }
    }

    return [base];
}

export function isParameterOwnedByFeature(feature: FeatureName, paramName: string): boolean;
export function isParameterOwnedByFeature(paramName: string, feature: FeatureName): boolean;
export function isParameterOwnedByFeature(arg1: string, arg2: string): boolean {
    let feature: FeatureName;
    let paramName: string;

    if (arg1 in FEATURE_QUERY_PARAMETERS) {
        feature = arg1 as FeatureName;
        paramName = arg2;
    } else {
        paramName = arg1;
        feature = arg2 as FeatureName;
    }

    if (!feature || !(feature in FEATURE_QUERY_PARAMETERS)) return false;
    const config = FEATURE_QUERY_PARAMETERS[feature];
    const base = paramName.replace(/\[\]$/, "");
    return (
        (config.parameters as readonly string[]).includes(base) ||
        (config.legacy_aliases as readonly string[]).includes(base)
    );
}

const isPastBillsOfTheMonthPath = (pathname: string): boolean => {
    const cleanPath = (pathname.split("?")[0] ?? "").split("#")[0] ?? "";
    return /^\/past_bills_of_the_month/.test(cleanPath);
};

const isCrossBillsSurfaceNavigation = (
    destFeature: FeatureName | null,
    sourceFeature: FeatureName | null,
    destinationPath: string,
    sourcePath?: string | null,
): boolean => {
    if (destFeature !== "bills" || sourceFeature !== "bills" || !sourcePath) {
        return false;
    }
    return isPastBillsOfTheMonthPath(destinationPath) !== isPastBillsOfTheMonthPath(sourcePath);
};

const addFeatureParameters = (allowed: Set<string>, feature: FeatureName | null): void => {
    if (!feature) return;
    const config = FEATURE_QUERY_PARAMETERS[feature];
    config.parameters.forEach((p) => allowed.add(p));
    config.legacy_aliases.forEach((a) => allowed.add(a));
};

export const getAllowedCarryParametersForPath = (
    destinationPath: string,
    sourcePath?: string | null,
    isGet = true,
): Set<string> => {
    const allowed = new Set<string>(GLOBAL_AMBIENT_QUERY_PARAMETERS);
    const destFeature = getFeatureForPath(destinationPath);
    const sourceFeature = sourcePath ? getFeatureForPath(sourcePath) : null;

    if (!isGet) {
        if (!isCrossBillsSurfaceNavigation(destFeature, sourceFeature, destinationPath, sourcePath)) {
            addFeatureParameters(allowed, destFeature);
            addFeatureParameters(allowed, sourceFeature);
        }
    } else if (sourcePath === undefined || sourcePath === null) {
        addFeatureParameters(allowed, destFeature);
    } else if (
        sourceFeature &&
        sourceFeature === destFeature &&
        !isCrossBillsSurfaceNavigation(destFeature, sourceFeature, destinationPath, sourcePath)
    ) {
        addFeatureParameters(allowed, destFeature);
    }

    if (isPastBillsOfTheMonthPath(destinationPath)) {
        allowed.delete("bills_legislative_session_id");
        allowed.delete("legislative_session_id");
    }
    return allowed;
};
