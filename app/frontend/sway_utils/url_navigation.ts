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

export { setQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";
