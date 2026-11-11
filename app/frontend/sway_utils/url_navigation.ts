import { router } from "@inertiajs/react";
import { notify } from "app/frontend/sway_utils";
import { setQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";

export interface NavigateWithParamsOptions {
    only: string[];
    resetParams?: string[];
    errorTitle: string;
}

export const navigateWithParams = (
    mutate: (params: URLSearchParams) => void,
    { only, resetParams = [], errorTitle }: NavigateWithParamsOptions,
): void => {
    const params = new URLSearchParams(window.location.search);
    mutate(params);
    resetParams.forEach((param) => {
        if (params.has(param)) {
            setQueryParamCleared(params, param);
        }
    });
    const qs = params.toString();

    router.get(
        `${window.location.pathname}${qs ? `?${qs}` : ""}`,
        {},
        {
            preserveScroll: true,
            preserveState: true,
            only,
            onError: () => notify({ level: "error", title: errorTitle }),
        },
    );
};

export {
    NAVIGATION_EXCLUDED_ROUTE_PREFIXES,
    type NavigationExcludedRoutePrefix,
    isNavigationExcludedRoute,
    normalizeNavigationPathname,
} from "app/frontend/sway_constants/navigation";

export {
    setQueryParamCleared,
    isQueryParamCleared,
    stripClearedQueryParams,
    stripClearedQueryParamsFromVisit,
    registerClearedParamStripPoint,
    unregisterClearedParamStripPoint,
} from "app/frontend/sway_utils/queryParamClearedSignal";

export {
    GLOBAL_AMBIENT_QUERY_PARAMETERS,
    type GlobalAmbientQueryParameter,
    FEATURE_QUERY_PARAMETERS,
    type FeatureName,
    getFeatureForPath,
    isGlobalAmbientParameter,
    getAllowedCarryParametersForPath,
} from "app/frontend/sway_constants/queryParameters";

export {
    applyNavigationCarryToVisit,
    registerQueryParamNavigationCarry,
    unregisterQueryParamNavigationCarry,
    isNavigationCarryRegistered,
    type NavigationCarryOptions,
} from "app/frontend/sway_utils/queryParamNavigationCarry";
