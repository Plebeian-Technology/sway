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
    "X-CSRF-Token":
        (document.querySelector("meta[name=csrf-token]") as HTMLMetaElement | undefined)?.content ||
        getCookies()["XSRF-TOKEN"],
};

export const useFetch = <T>(route: string, options?: Record<string, any>) => {
    return useCallback(
        (body: Record<string, any>) => {
            return fetch(route, {
                body: JSON.stringify(body),
                method: "POST",
                headers: HEADERS,
                signal: AbortSignal.timeout(
                    Number((typeof options?.timeout === "number" ? options.timeout : 1000) * 120),
                ), // 2 minutes
            })
                .then((r) => r.json() as Promise<T>)
                .catch(console.error);
        },
        [route, options],
    );
};
