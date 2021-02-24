import { CLOUD_FUNCTIONS } from "@sway/constants";
import { useEffect, useState } from "react";
import { sway } from "sway";
import { functions } from "../firebase";
import { AWARD_TYPES, handleError } from "../utils";

export const useCongratulations = (): [
    boolean,
    (congratulations: boolean) => void,
] => {
    return useState<boolean>(false);
};

export const useAwardCount = (
    user: sway.IUser,
    locale: sway.IUserLocale | sway.ILocale,
    type: sway.TAwardType,
): number => {
    const [count, setCount] = useState<number>(-1);

    const uid = user?.uid;

    useEffect(() => {
        const getter = functions.httpsCallable(CLOUD_FUNCTIONS.getUserSway);
        getter({ uid: uid, locale: locale })
            .then(
                (response: firebase.default.functions.HttpsCallableResult) => {
                    const data = response.data;
                    if (type === AWARD_TYPES.Vote) {
                        setCount(data.userSway.countBillsVotedOn);
                    } else if (type === AWARD_TYPES.Invite) {
                        setCount(data.userSway.countInvitesSent);
                    } else if (type === AWARD_TYPES.BillShare) {
                        setCount(data.userSway.countAllBillShares);
                    } else if (type === AWARD_TYPES.Sway) {
                        setCount(
                            Object.keys(data).reduce(
                                (sum: number, key: string) => {
                                    if (key.includes("count")) {
                                        return sum + data[key];
                                    }
                                    return sum;
                                },
                                0,
                            ),
                        );
                    } else {
                        console.error(`Award type - ${type} - has no data.`);
                    }
                },
            )
            .catch(handleError);
    }, [uid, locale, setCount]);

    return count;
};
