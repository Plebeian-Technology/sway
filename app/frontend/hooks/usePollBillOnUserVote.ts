import { router } from "@inertiajs/react";
import { logDev } from "app/frontend/sway_utils";
import { useCallback, useEffect, useState } from "react";

const MAX_ITERATIONS = 5;

export const usePollBillOnUserVote = () => {
    const [voted, setVoted] = useState<boolean>(false);
    const [iterations, setIterations] = useState<number>(0);

    const onUserVote = useCallback(() => {
        setVoted(true);
    }, []);

    const onScoreReceived = useCallback(() => {
        setVoted(false);
    }, []);

    useEffect(() => {
        if (iterations >= MAX_ITERATIONS) {
            const t = window.setTimeout(() => {
                setIterations(0);
                setVoted(false);
            }, 0);
            return () => window.clearTimeout(t);
        } else if (iterations < MAX_ITERATIONS && voted) {
            const t = window.setTimeout(() => {
                logDev("usePollBillOnUserVote.useEffect - reloading page. Iteration -", iterations);
                router.reload({
                    fresh: true,
                    onFinish: () => {
                        setIterations((current) => current + 1);
                    },
                });
            }, 1000);
            return () => window.clearTimeout(t);
        }
    }, [iterations, voted]);

    return { onUserVote, onScoreReceived };
};
