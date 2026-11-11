import { TempBillStorage } from "app/frontend/components/bill/creator/TempBillStorage";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

export const useTempStorage = <T extends object>(key: string, data: T | (() => T)) => {
    const storage = useMemo(() => new TempBillStorage(key), [key]);

    const [blurredFieldName, setBlurredFieldName] = useState<string>("");

    const storeTempData = useCallback(
        (override?: Record<string, unknown>) => {
            // @lat: [[select-field-autosave-draft-timing-bug#The second bug hiding behind the first: stale payload contents]]
            const base = typeof data === "function" ? data() : data;
            storage.set(override ? { ...base, ...override } : base);
        },
        [storage, data],
    );

    // @lat: [[bill-creator-temp-storage-hook#Why the hide-indicator timer restarts on every blur]]
    const clearTimerRef = useRef<number | null>(null);

    // @lat: [[select-field-autosave-draft-timing-bug#Why SelectField.test.tsx's Select stand-in reproduces Radix's callback order]]
    const storeField = useCallback(
        (name: string, override?: Record<string, unknown>) => {
            storeTempData(override);
            setBlurredFieldName(name);
            if (clearTimerRef.current) {
                window.clearTimeout(clearTimerRef.current);
            }
            clearTimerRef.current = window.setTimeout(() => setBlurredFieldName(""), 3000);
        },
        [storeTempData],
    );

    // @lat: [[bill-creator-temp-storage-hook#Why onBlur is a narrower union than it used to be]]
    const onBlur = useCallback(
        (e: React.FocusEvent<HTMLInputElement | HTMLTextAreaElement>) => storeField(e.target.name),
        [storeField],
    );

    // @lat: [[bill-creator-temp-storage-hook#Why the cleanup effect cancels the hide timer on unmount]]
    useEffect(
        () => () => {
            if (clearTimerRef.current) {
                window.clearTimeout(clearTimerRef.current);
            }
        },
        [],
    );

    return { storage, blurredFieldName, onBlur, storeField };
};
