import { handleRoutedResponse } from "app/frontend/hooks/useAxios";
import { useCallback } from "react";

const getCookies = () =>
    document.cookie.split(";").reduce((sum, kvString) => {
        const [key, value] = kvString.split("=");
        return {
            ...sum,
            [key.trim()]: value.trim(),
        };
    }, {}) as Record<string, string>;

const HEADERS = {
    "Content-Type": "application/json",
    Accept: "application/json",
};

export const useFetch = <T extends Record<string, any> | void>(route: string, options?: Record<string, any>) => {
    return useCallback(
        (body: Record<string, any>) => {
            return fetch(route, {
                body: JSON.stringify(body),
                method: "POST",
                headers: {
                    ...HEADERS,
                    "X-CSRF-Token": getCookies()["XSRF-TOKEN"],
                    "X-XSRF-Token": getCookies()["XSRF-TOKEN"],
                },
                signal: AbortSignal.timeout(
                    Number((typeof options?.timeout === "number" ? options.timeout : 1000) * 120),
                ), // 2 minutes
            })
                .then((r) => r.json() as Promise<T>)
                .then((j) => {
                    if (j && "route" in j && j.route) {
                        handleRoutedResponse(j);
                    }
                    return j;
                })
                .catch(console.error);
        },
        [route, options],
    );
};
