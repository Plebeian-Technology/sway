import { router } from "@inertiajs/react";
import axios, { AxiosError, AxiosResponse } from "axios";
import { useCallback, useEffect, useMemo, useState } from "react";
import { sway } from "sway";
import { DEFAULT_ERROR_MESSAGE, handleError, logDev, notify } from "../sway_utils";
import { isFailedRequest } from "../sway_utils/http";
import { useCancellable } from "./useCancellable";

type TPayload = Record<number, any> | Record<string, any> | FormData;

type TQueryRequest = (route: string, errorHandler?: (error: AxiosError) => void) => Promise<AxiosResponse | void>;

type TBodyRequest = (
    route: string,
    data: TPayload | null,
    errorHandler?: (error: AxiosError) => void,
) => Promise<AxiosResponse | void>;

interface IRoutableResponse {
    route?: string;
    phone?: string;
    params?: Record<string, any>;
}

/*
 * ERROR HANDLING
 */

const handleAxiosError = (ex: AxiosError | Error) => {
    if (ex instanceof AxiosError) {
        if (ex?.response?.status === 400 && ex.response.statusText) {
            // 400, SwayInvalidRequestException
            notify({
                level: "error",
                title: "Error using Sway",
                message: ex.response.statusText,
            });
        } else {
            handleError(ex);
        }
    } else {
        console.error(ex);
    }
};

export const handleRoutedResponse = <T extends Record<string, any>>(result: IRoutableResponse | T) => {
    if (result.phone) {
        // localStorage.setItem("@sway/phone", removeNonDigits(result.phone));
    }
    if (result.route) {
        router.get(result.route, { ...result.params });
    }
    return result;
};

/*
 *
 * SECURE/SESSION METHODS
 *
 */

export const useAxiosGet = <T extends Record<string, any>>(
    route: string,
    options?: {
        notifyOnValidationResultFailure?: boolean;
        skipInitialRequest?: boolean;
        defaultValue?: T;
        method?: "get" | "delete";
        callback?: () => void;
    },
) => {
    const getter = useAxiosAuthenticatedGet(options?.method);
    const [items, setItems] = useState<T | undefined>(options?.defaultValue);
    const [isLoading, setLoading] = useState<boolean>(false);

    const get = useCallback(
        async (opts?: { route?: string; params?: Record<string, string | number | boolean> }) => {
            if (!route || route.includes("undefined")) {
                if (options?.defaultValue) {
                    setItems(options.defaultValue);
                }
                return options?.defaultValue;
            }

            setLoading(true);

            const endpoint = opts?.route || route;
            const params = opts?.params;
            const r = params
                ? `${endpoint}?${Object.keys(params)
                      .map((k) => `${k}=${params[k]}`)
                      .join("&")}`
                : endpoint;

            return getter(r)
                .then((response: AxiosResponse | void) => {
                    if (options?.callback) {
                        logDev("useAxiosGet.options.callback");
                        options.callback();
                    }

                    setLoading(false);
                    const result = response && (response.data as T | sway.IValidationResult);

                    if (!result) {
                        if (options?.defaultValue) {
                            setItems(options.defaultValue);
                        }
                        return options?.defaultValue;
                    } else if (isFailedRequest(result)) {
                        if (options?.notifyOnValidationResultFailure) {
                            notify({
                                level: "warning",
                                title: (result as sway.IValidationResult)?.message || DEFAULT_ERROR_MESSAGE,
                                // message: (result as sway.IValidationResult)?.message || DEFAULT_ERROR_MESSAGE,
                            });
                        } else if ("route" in result && result.route) {
                            return handleRoutedResponse(result);
                        } else if (options?.defaultValue) {
                            setItems(options.defaultValue);
                        } else {
                            return options?.defaultValue || result;
                        }
                    } else {
                        setItems(result as T);
                        return result;
                    }
                })
                .catch((e) => {
                    setLoading(false);
                    handleError(e);
                    if (options?.defaultValue) {
                        setItems(options.defaultValue);
                    }
                    return options?.defaultValue;
                });
        },
        [route, getter, options],
    );

    useEffect(() => {
        if (!options?.skipInitialRequest) {
            get().catch(console.error);
        }
    }, [get, options?.skipInitialRequest]);

    return { items, setItems, isLoading, setLoading, get };
};

export const useAxiosPost = <T extends Record<string, any>>(
    route: string,
    options?: {
        notifyOnValidationResultFailure?: boolean;
        defaultValue?: T;
        method?: "post" | "put";
    },
) => {
    const poster = useAxiosAuthenticatedPostPut(options?.method);
    const [items, setItems] = useState<T | undefined>();
    const [isLoading, setLoading] = useState<boolean>(false);

    const post = useCallback(
        async (data: Record<string, any> | undefined | null, opts?: { route: string }): Promise<T | null> => {
            const r = opts?.route || route;
            if (!r || r.includes("undefined") || !data) {
                return null;
            }

            setLoading(true);

            return poster(r, data)
                .then(async (response: AxiosResponse | void): Promise<T | null> => {
                    // 503 responses when backend is shutting down and db session is null or closed.
                    if (response && response.status === 503) {
                        return new Promise((resolve) => {
                            window.setTimeout(() => {
                                resolve(post(data));
                            }, 100);
                        });
                    }

                    setLoading(false);

                    const result = response && (response.data as T | sway.IValidationResult);
                    if (!result) {
                        return null;
                    } else if ("route" in result && result.route) {
                        return handleRoutedResponse(result) as T;
                    } else if (isFailedRequest(result)) {
                        if (options?.notifyOnValidationResultFailure) {
                            notify({
                                level: "warning",
                                title: "Request failed.",
                                message: (result as sway.IValidationResult).message || DEFAULT_ERROR_MESSAGE,
                            });
                        }
                        return null;
                    } else {
                        setItems(result as T);
                        return result as T;
                    }
                })
                .catch((e) => {
                    setLoading(false);
                    handleError(e);
                    return null;
                });
        },
        [poster, route, options?.notifyOnValidationResultFailure],
    );

    return { isLoading, setLoading, post, items };
};

const useAxiosAuthenticatedGet = (method: "get" | "delete" = "get"): TQueryRequest => {
    const caller = useAxiosAuthenticatedRequest(method) as TBodyRequest;

    const options = useMemo(() => ({}), []);
    return useCallback(
        (route: string, errorHandler?: (error: AxiosError) => void) => {
            return caller(route, options, errorHandler);
        },
        [options, caller],
    ) as TQueryRequest;
};

const useAxiosAuthenticatedPostPut = (method: "post" | "put" = "post"): TBodyRequest => {
    const options = useMemo(() => ({}), []);
    return useAxiosAuthenticatedRequest(method, options) as TBodyRequest;
};
/**
 * Used when a user has authenticated with Sway and has been granted a session
 *
 * @param method
 * @param options
 * @returns
 */
const useAxiosAuthenticatedRequest = (
    method: "put" | "post" | "get" | "delete", // NOSONAR
    options?: Record<string, string>,
): TQueryRequest | TBodyRequest => {
    // * Forces a page refresh at 3:00 AM each night

    const makeCancellable = useCancellable();
    return useCallback(
        (route_: string, data: TPayload | null, errorHandler?: (error: AxiosError) => void) => {
            const errorHandler_ = errorHandler || handleAxiosError;

            const route = route_.replace(/\s/g, "");
            const opts = { withCredentials: true, ...options } as Record<string, any>;

            // * ************************************************************
            // * WARNING: Axios handles the below automatically.
            // * WARNING: ****** IF THIS IS SET THE REQUEST WILL FAIL ******
            // * ************************************************************
            // if (data instanceof FormData) {
            //     (opts as Record<string, any>)["headers"] = { "Content-Type": "Multipart/Form-Data" };
            // }

            // const url = (() => {
            //     if (route.startsWith(BASE_API_URL)) {
            //         return route;
            //     } else {
            //         return `${BASE_API_URL}/${BASE_AUTHED_ROUTE_V1}` + (route.startsWith("/") ? route : `/${route}`);
            //     }
            // })();
            const url = route;

            const request =
                data === null
                    ? () =>
                          axios.request({
                              method,
                              url,
                              signal: AbortSignal.timeout(Number(options?.timeout || 1000 * 120)), // 2 minutes
                              headers: {
                                  ...opts.headers,
                                  // https://stackoverflow.com/a/56144709/6410635
                                  "X-CSRF-Token": getCookies()["XSRF-TOKEN"],
                                  // "Cache-Control": "no-cache",
                                  // Pragma: "no-cache",
                                  // Expires: "0",
                              },
                              ...opts,
                          })
                    : () =>
                          axios.request({
                              method,
                              url,
                              data,
                              signal: AbortSignal.timeout(Number(options?.timeout || 1000 * 120)), // 2 minutes
                              headers: {
                                  ...opts.headers,
                                  // https://stackoverflow.com/a/56144709/6410635
                                  "X-CSRF-Token": getCookies()["XSRF-TOKEN"],
                                  // "Cache-Control": "no-cache",
                                  // Pragma: "no-cache",
                                  // Expires: "0",
                              },
                              ...opts,
                          });

            return makeCancellable(request().catch(errorHandler_), () =>
                logDev(`Canceled Axios AUTHENTICATED ${method.toUpperCase()} to route -`, url),
            );
        },
        [method, options, makeCancellable],
    );
};

/*
 *
 * NO_AUTH METHODS
 *
 */

const useAxiosPublicGet = (
    method: "get" | "delete",
): ((route: string, errorHandler?: (error: AxiosError) => void) => Promise<AxiosResponse | void>) => {
    const options = useMemo(() => ({}), []);
    const caller = useAxiosPublicRequest(method, options);
    return useCallback(
        (route: string, errorHandler?: (error: AxiosError) => void) => {
            return caller(route, options, errorHandler);
        },
        [options, caller],
    );
};

const useAxiosPublicPostPut = (
    method: "post" | "put" = "post",
): ((route: string, data: TPayload, errorHandler?: (error: AxiosError) => void) => Promise<AxiosResponse | void>) => {
    const options = useMemo(() => ({}), []);
    return useAxiosPublicRequest(method, options);
};

export const useAxios_NOT_Authenticated_GET = <T extends Record<string, any>>(
    route: string,
    options?: { notifyOnValidationResultFailure?: boolean; skipInitialRequest?: boolean; method?: "get" | "delete" },
) => {
    const getter = useAxiosPublicGet(options?.method ?? "get");
    const [items, setItems] = useState<T | undefined>();
    const [isLoading, setLoading] = useState<boolean>(false);

    const get = useCallback(
        async (opts?: { route?: string; params?: Record<string, string | number | boolean> }): Promise<T | null> => {
            if (!route || route.includes("undefined")) {
                return null;
            }

            setLoading(true);

            const endpoint = opts?.route || route;
            const params = opts?.params;
            const r = params
                ? `${endpoint}?${Object.keys(params)
                      .map((k) => `${k}=${params[k]}`)
                      .join("&")}`
                : endpoint;

            return getter(r)
                .then(async (response: AxiosResponse | void): Promise<T | null> => {
                    setLoading(false);

                    const result = response?.data as T | sway.IValidationResult | IRoutableResponse;
                    if (!result) {
                        return null;
                    } else if ("route" in result && result.route) {
                        return handleRoutedResponse(result) as T;
                    } else if (isFailedRequest(result)) {
                        if (options?.notifyOnValidationResultFailure) {
                            notify({
                                level: "warning",
                                title: "Request failed.",
                                message: (result as sway.IValidationResult).message || DEFAULT_ERROR_MESSAGE,
                            });
                        }
                        return null;
                    } else {
                        setItems(result as T);
                        return result as T;
                    }
                })
                .catch((e) => {
                    setLoading(false);
                    handleError(e);
                    return null;
                });
        },
        [getter, route, options?.notifyOnValidationResultFailure],
    );

    useEffect(() => {
        if (!options?.skipInitialRequest) {
            get().catch(console.error);
        }
    }, [get, options?.skipInitialRequest]);

    return { items, setItems, isLoading, setLoading, get };
};

interface IPostOptions {
    notifyOnValidationResultFailure?: boolean;
    errorHandler?: (e: AxiosError) => void;
    method?: "post" | "put";
}

export const useAxios_NOT_Authenticated_POST_PUT = <T extends Record<string, any>>(
    route: string,
    { notifyOnValidationResultFailure, errorHandler, method }: IPostOptions = { method: "post" },
) => {
    const poster = useAxiosPublicPostPut(method);
    const [items, setItems] = useState<T | undefined>();
    const [isLoading, setLoading] = useState<boolean>(false);

    const post = useCallback(
        async (data: Record<string, any> | undefined | null): Promise<T | sway.IValidationResult | null> => {
            if (!route || route.includes("undefined") || !data) {
                return null;
            }

            setLoading(true);

            return poster(route, data, errorHandler)
                .then(async (response: AxiosResponse | void): Promise<T | sway.IValidationResult | null> => {
                    // 503 responses when backend is shutting down and db session is null or closed.
                    if (response && response.status === 503) {
                        return new Promise((resolve) => {
                            window.setTimeout(() => {
                                resolve(post(data));
                            }, 100);
                        });
                    }

                    setLoading(false);
                    const result = response && (response.data as T | sway.IValidationResult);
                    if (!result) {
                        return null;
                    } else if ("route" in result && result.route) {
                        return handleRoutedResponse(result) as T;
                    } else if (isFailedRequest(result)) {
                        if (notifyOnValidationResultFailure) {
                            notify({
                                level: "warning",
                                title: "Request failed.",
                                message: (result as sway.IValidationResult).message || DEFAULT_ERROR_MESSAGE,
                            });
                        }
                        return result;
                    } else {
                        setItems(result as T);
                        return result as T;
                    }
                })
                .catch((e) => {
                    setLoading(false);
                    (errorHandler || handleError)(e);
                    return null;
                });
        },
        [route, poster, errorHandler, notifyOnValidationResultFailure],
    );
    return { isLoading, setLoading, post, items, setItems };
};

/**
 * Use when a user has NOT authenticated with Sway and been given a session.
 *
 * @param method
 * @param options
 * @returns
 */
const useAxiosPublicRequest = (
    method: "put" | "post" | "get" | "delete",
    options: Record<string, string> = {},
): ((
    route: string,
    data: TPayload | null,
    errorHandler?: (error: AxiosError) => void,
) => Promise<AxiosResponse | void | undefined>) => {
    const makeCancellable = useCancellable();

    return useCallback(
        async (route_: string, data: TPayload | null, errorHandler?: (error: AxiosError) => void) => {
            let route = `${window.location.origin}/${route_.replace(/\s/g, "")}`; // remove all whitespace

            if (method !== "get" && route === "/") {
                return;
            }

            const opts = {
                withCredentials: true,
                ...options,
            };

            if (data instanceof FormData) {
                (opts as Record<string, any>)["headers"] = {
                    "content-type": "multipart/form-data",
                };
                (opts as Record<string, any>)["timeout"] = 0; // infinite, default?
            }

            if (data === null) {
                data = opts; // eslint-disable-line
            }

            const errorHandler_ = errorHandler || handleAxiosError;

            const sendPublicRequest = (token: string | undefined) => {
                if (token) {
                    if (!route.includes("token=")) {
                        if (route.includes("?")) {
                            route = `${route}&token=${token}`;
                        } else {
                            route = `${route}?token=${token}`;
                        }
                    }
                }

                return makeCancellable(
                    axios
                        .request({
                            ...opts,
                            url: route,
                            method,
                            data: { token, ...data },
                            headers: {
                                // https://stackoverflow.com/a/56144709/6410635
                                "X-CSRF-Token": getCookies()["XSRF-TOKEN"],
                                // "Cache-Control": "no-cache",
                                // Pragma: "no-cache",
                                // Expires: "0",
                            },
                        })
                        .catch(errorHandler_),
                    () => logDev(`Canceled Axios NO_AUTH ${method.toUpperCase()} to route -`, route),
                );
            };

            return sendPublicRequest(undefined).catch((e) => (errorHandler || console.error)(e));
        },
        [options, method, makeCancellable],
    );
};

const getCookies = () =>
    document.cookie.split(";").reduce((sum, kvString) => {
        const [key, value] = kvString.split("=");
        return {
            ...sum,
            [key.trim()]: value.trim(),
        };
    }, {}) as Record<string, string>;
