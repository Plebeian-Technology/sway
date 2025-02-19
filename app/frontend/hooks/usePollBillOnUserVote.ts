import { router } from "@inertiajs/react";
import { useCallback, useEffect, useState } from "react";

export const usePollBillOnUserVote = () => {
    const [voted, setVoted] = useState<boolean>(false);
    const [int, setInt] = useState<number | undefined>();

    const onUserVote = useCallback(() => {
        setVoted(true);
    }, []);

    const onScoreReceived = useCallback(() => {
        setVoted(false);
    }, []);

    useEffect(() => {
        if (voted && int === undefined) {
            setInt(
                window.setInterval(() => {
                    router.reload({ fresh: true });
                }, 1000),
            );
        }
        if (!voted && int !== undefined) {
            window.clearInterval(int);
            setInt(undefined);
        }
    }, [int, voted]);

    return { onUserVote, onScoreReceived };
};
