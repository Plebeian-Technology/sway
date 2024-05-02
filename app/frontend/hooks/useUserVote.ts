/** @format */

import { useEffect, useState } from "react";
import { sway } from "sway";
import { swayFireClient } from "../sway_utils";
import { useFirebaseUser } from "./users/useFirebaseUser";

export const useUserVote = (
    user: sway.IUser | undefined,
    locale: sway.ISwayLocale | undefined,
    billFirestoreId: string,
): [sway.IUserVote | undefined, boolean] => {
    const [firebaseUser] = useFirebaseUser();
    const [userVote, setUserVote] = useState<sway.IUserVote | undefined>();
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const uid = user?.uid;
    const isAnonymous = firebaseUser?.isAnonymous;

    useEffect(() => {
        const load = async () => {
            if (!uid || !locale || !billFirestoreId || isAnonymous) return;
            setIsLoading(true);
            const _userVote = await swayFireClient(locale).userVotes(uid).get(billFirestoreId);
            setUserVote(_userVote as sway.IUserVote);
            setIsLoading(false);
        };
        load().catch((error) => {
            console.error(error);
            setIsLoading(false);
        });
    }, [uid, locale, billFirestoreId, setUserVote, setIsLoading, isAnonymous]);

    return [userVote, isLoading];
};
