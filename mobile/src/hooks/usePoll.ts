// @lat: [[mobile-sync-hooks#usePoll]]
import { useEffect } from "react";

export function usePoll(ms: number, onPoll: () => void): void {
    useEffect(() => {
        const id = setInterval(onPoll, ms);
        return () => clearInterval(id);
    }, [ms, onPoll]);
}
