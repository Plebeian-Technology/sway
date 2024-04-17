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
        <T>(promise: Promise<T>, onCancel?: () => void) =>
            new Promise<T>((resolve, reject) => {
                promise
                    .then((result) => {
                        if (isMounted()) {
                            resolve(result);
                        }
                    })
                    .catch((error) => {
                        if (isMounted()) {
                            reject(error);
                        }
                    })
                    .finally(() => {
                        if (!isMounted() && onCancel) {
                            onCancel();
                        }
                    });
            }),
        [isMounted],
    );
};
