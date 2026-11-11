import { useCallback } from "react";

import { navigateWithParams, setQueryParamCleared } from "app/frontend/sway_utils/url_navigation";

// @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
interface IUrlSortConfig<T extends string> {
    options: readonly T[];
    defaultValue: T;
    only: string[];
    resetParams?: string[];
    errorTitle: string;
    sortParam: string;
    directionParam: string;
    legacySortAliases?: string[];
    legacyDirectionAliases?: string[];
}

// @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
export const useUrlSort = <T extends string>({
    options,
    defaultValue,
    only,
    resetParams = [],
    errorTitle,
    sortParam,
    directionParam,
    legacySortAliases = [],
    legacyDirectionAliases = [],
}: IUrlSortConfig<T>) => {
    // @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    let value = defaultValue;
    if (typeof window !== "undefined") {
        const params = new URLSearchParams(window.location.search);
        let column: string | null = null;
        if (params.has(sortParam)) {
            column = params.get(sortParam);
        } else {
            for (const alias of legacySortAliases) {
                if (params.has(alias)) {
                    column = params.get(alias);
                    break;
                }
            }
        }
        column = column || defaultValue.split(":")[0];

        let directionRaw: string | null = null;
        if (params.has(directionParam)) {
            directionRaw = params.get(directionParam);
        } else {
            for (const alias of legacyDirectionAliases) {
                if (params.has(alias)) {
                    directionRaw = params.get(alias);
                    break;
                }
            }
        }
        const direction = directionRaw === "asc" ? "asc" : "desc";
        value = options.find((option) => option === `${column}:${direction}`) ?? defaultValue;
    }

    const onChange = useCallback(
        (next: T) => {
            const [column, direction] = next.split(":");
            navigateWithParams(
                (params) => {
                    if (next === defaultValue) {
                        setQueryParamCleared(params, sortParam);
                        setQueryParamCleared(params, directionParam);
                    } else {
                        params.set(sortParam, column);
                        params.set(directionParam, direction);
                    }
                    legacySortAliases.forEach((alias) => {
                        if (params.has(alias)) {
                            setQueryParamCleared(params, alias);
                        } else {
                            params.delete(alias);
                        }
                    });
                    legacyDirectionAliases.forEach((alias) => {
                        if (params.has(alias)) {
                            setQueryParamCleared(params, alias);
                        } else {
                            params.delete(alias);
                        }
                    });
                },
                { only, resetParams, errorTitle },
            );
        },
        [
            defaultValue,
            sortParam,
            directionParam,
            legacySortAliases,
            legacyDirectionAliases,
            only,
            resetParams,
            errorTitle,
        ],
    );

    return { value, onChange };
};
