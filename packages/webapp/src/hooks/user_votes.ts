/** @format */

import { sway } from "sway";
import { useEffect, useState } from "react";
import { legisFire } from "../utils";
import { useUser } from "./users";

export const useUserVote = (
    billFirestoreId: string,
): [sway.IUserVote | undefined, boolean] => {
    const user = useUser();
    const [userVote, setUserVote] = useState<sway.IUserVote | undefined>();
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const uid = user?.uid;
    const locale = user?.locale;

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
