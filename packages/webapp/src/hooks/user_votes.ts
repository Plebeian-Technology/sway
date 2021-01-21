/** @format */

import { useEffect, useState } from "react";
import { sway } from "sway";
import { legisFire } from "../utils";

export const useUserVote = (
    user: sway.IUser | undefined,
    locale: sway.ILocale | undefined,
    billFirestoreId: string,
): [sway.IUserVote | undefined, boolean] => {
    const [userVote, setUserVote] = useState<sway.IUserVote | undefined>();
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const uid = user?.uid;

    useEffect(() => {
        const load = async () => {
            if (!uid || !locale || !billFirestoreId) return;
            setIsLoading(true);
            const _userVote = await legisFire({
                name: locale.name,
            } as sway.ILocale)
                .userVotes(uid)
                .get(billFirestoreId);
            setUserVote(_userVote as sway.IUserVote);
            setIsLoading(false);
        };
        load().catch((error) => {
            console.error(error);
            setIsLoading(false);
        });
    }, [uid, locale, billFirestoreId, setUserVote, setIsLoading]);

    return [userVote, isLoading];
};
