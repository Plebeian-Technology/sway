// @lat: [[mobile-admin-area#Admin writes]]
import { useCallback, useState } from "react";

import { apiClient } from "../../api/client";
import { ApiRequestError, GENERIC_ERROR_MESSAGE } from "../../api/errors";
import { assertOnlineForWrite } from "../useOfflineCache";
import { useReachability } from "../useReachability";

export const ADMIN_OFFLINE_MESSAGE = "You need a connection to make this change.";

export type AdminMutationMethod = "post" | "patch" | "delete";

export interface UseAdminMutationResult<TResponse> {
    run: (body?: unknown) => Promise<TResponse | null | undefined>;
    loading: boolean;
    errorMessage: string | null;
    fieldErrors: Record<string, unknown> | null;
    errorStatus: number | null;
}

export function useAdminMutation<TResponse = void>(
    method: AdminMutationMethod,
    path: string,
): UseAdminMutationResult<TResponse> {
    const reach = useReachability();
    const [loading, setLoading] = useState(false);
    const [errorMessage, setErrorMessage] = useState<string | null>(null);
    const [fieldErrors, setFieldErrors] = useState<Record<string, unknown> | null>(null);
    const [errorStatus, setErrorStatus] = useState<number | null>(null);

    const run = useCallback(
        async (body?: unknown): Promise<TResponse | null | undefined> => {
            setLoading(true);
            setErrorMessage(null);
            setFieldErrors(null);
            setErrorStatus(null);
            try {
                assertOnlineForWrite(reach.isOnline);
                const response =
                    method === "delete"
                        ? await apiClient.delete<TResponse>(path)
                        : await apiClient[method]<TResponse>(path, body);
                return response ?? null;
            } catch (e: unknown) {
                if (e instanceof ApiRequestError) {
                    setErrorMessage(e.message);
                    setFieldErrors(e.details ?? null);
                    setErrorStatus(e.status ?? null);
                } else if (e instanceof Error && e.message === "offline_write_blocked") {
                    setErrorMessage(ADMIN_OFFLINE_MESSAGE);
                } else {
                    setErrorMessage(GENERIC_ERROR_MESSAGE);
                }
                return undefined;
            } finally {
                setLoading(false);
            }
        },
        [method, path, reach.isOnline],
    );

    return { run, loading, errorMessage, fieldErrors, errorStatus };
}
