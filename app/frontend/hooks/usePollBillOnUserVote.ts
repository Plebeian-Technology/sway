import { router } from "@inertiajs/react";
import { useCallback, useEffect, useState } from "react";

const MAX_ITERATIONS = 3;

export const usePollBillOnUserVote = () => {
    const [voted, setVoted] = useState<boolean>(false);
    const [int, setInt] = useState<number | undefined>();
    const [iterations, setIterations] = useState<number>(0);

    const onUserVote = useCallback(() => {
        setVoted(true);
    }, []);

    const onScoreReceived = useCallback(() => {
        setVoted(false);
    }, []);

    useEffect(() => {
        if (iterations >= MAX_ITERATIONS) {
            setInt(undefined);
            setIterations(0);
            window.clearInterval(int);
        } else if (!voted && int !== undefined) {
            window.clearInterval(int);
            setInt(undefined);
        } else if (iterations < MAX_ITERATIONS && voted && int === undefined) {
            setInt(
                window.setInterval(() => {
                    setIterations((current) => current + 1);
                    router.reload({ fresh: true });
                }, 1000),
            );
        }
        return () => {
            if (int) {
                window.clearInterval(int);
            }
        };
    }, [int, iterations, voted]);

    return { onUserVote, onScoreReceived };
};
