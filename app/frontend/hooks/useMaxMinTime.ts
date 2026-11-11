import { useTime } from "app/frontend/hooks/useTime";
import { useMemo } from "react";

export function useMaxMinTime() {
    const minD = useTime();
    const maxD = useTime();

    const maxDate = useMemo(() => {
        maxD.setHours(maxD.getHours() + 24);
        return maxD;
    }, [maxD]);

    const minDate = useMemo(() => {
        minD.setFullYear(minD.getFullYear() - 4);
        return minD;
    }, [minD]);

    return {
        maxDate,
        minDate,
    };
}
