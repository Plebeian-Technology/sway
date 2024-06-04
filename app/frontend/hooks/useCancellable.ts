// https://github.com/rodw1995/use-cancelable-promise

import { useCallback, useEffect, useRef } from "react";

const useMountedState = (): (() => boolean) => {
    const mountedRef = useRef<boolean>(false);

    useEffect(() => {
        mountedRef.current = true;

        return () => {
            mountedRef.current = false;
        };
    });

    return useCallback(() => mountedRef.current, []);
};

export const useCancellable = () => {
    const isMounted = useMountedState();

    return useCallback(
        async <T>(promise: Promise<T>, onCancel?: () => void) =>
            // eslint-disable-next-line
            new Promise<T>(async (resolve, reject) => {
                // NOSONAR
                try {
                    const result = await promise;
                    if (isMounted()) {
                        resolve(result);
                    }
                } catch (error) {
                    if (isMounted()) {
                        reject(error as Error);
                    }
                } finally {
                    if (!isMounted() && onCancel) {
                        onCancel();
                    }
                }
            }),
        [isMounted],
    );
};
