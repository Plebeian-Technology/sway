/** @format */

import { useEffect, useState } from "react";
import { sway } from "sway";

export const useUserVote = (
    user: sway.IUser | undefined,
    locale: sway.ISwayLocale | undefined,
    billExternalId: string,
): [sway.IUserVote | undefined, boolean] => {
    const [userVote, setUserVote] = useState<sway.IUserVote | undefined>();
    const [isLoading, setIsLoading] = useState<boolean>(false);

    useEffect(() => {
        const load = async () => {
            if (!locale || !billExternalId) return;
            setIsLoading(true);
            // const _userVote = await swayFireClient(locale).userVotes(uid).get(billExternalId);
            // setUserVote(_userVote as sway.IUserVote);
            setIsLoading(false);
        };
        load().catch((error) => {
            console.error(error);
            setIsLoading(false);
        });
    }, [locale, billExternalId, setUserVote, setIsLoading]);

    return [userVote, isLoading];
};
