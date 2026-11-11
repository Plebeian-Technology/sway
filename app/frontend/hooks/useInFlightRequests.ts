import { useCallback, useRef, useState } from "react";

// @lat: [[private-individual-guard-override#A retry started from onError outlives the request that started it]]
export const useInFlightRequests = () => {
    const count = useRef<number>(0);
    const [inFlight, setInFlight] = useState<boolean>(false);

    const begin = useCallback(() => {
        count.current += 1;
        setInFlight(true);
    }, []);

    const end = useCallback(() => {
        count.current = Math.max(0, count.current - 1);
        setInFlight(count.current > 0);
    }, []);

    return { inFlight, begin, end };
};

export default useInFlightRequests;
