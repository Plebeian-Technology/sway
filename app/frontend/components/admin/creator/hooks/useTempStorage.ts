import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { useCallback, useEffect, useMemo, useState } from "react";

export const useTempStorage = (key: string, data: Record<string, any>) => {
    const storage = useMemo(() => new TempBillStorage(key), [key]);

    const [blurredFieldName, setBlurredFieldName] = useState<string>("");

    const storeTempData = useCallback(() => {
        storage.set(data);
    }, [storage, data]);

    const onBlur = useCallback(
        (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => {
            storeTempData();
            setBlurredFieldName(e.target.name);
        },
        [storeTempData],
    );

    useEffect(() => {
        const t = window.setTimeout(() => {
            setBlurredFieldName("");
        }, 3000);

        return () => {
            window.clearTimeout(t);
        };
    }, []);

    return { storage, blurredFieldName, onBlur };
};
