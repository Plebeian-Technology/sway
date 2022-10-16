import { CLOUD_FUNCTIONS } from "@sway/constants";
import { logDev } from "@sway/utils";
import { httpsCallable } from "firebase/functions";
import { useCallback, useEffect, useState } from "react";
import { sway } from "sway";
import { functions } from "../firebase";
import { AWARD_TYPES, handleError } from "../utils";
import { useCancellable } from "./cancellable";

export const useCongratulations = (): [boolean, (congrats: boolean) => void] => {
    const [congratulations, setCongratulations] = useState<boolean>(false);
    return [congratulations, setCongratulations];
};

interface IResponseData {
    locale: sway.IUserLocale;
    userSway: sway.IUserSway;
    localeSway: sway.IUserSway;
}

export const useAwardCount = (
    user: sway.IUser,
    locale: sway.IUserLocale | sway.ILocale,
    type: sway.TAwardType,
): number => {
    const makeCancellable = useCancellable();
    const [count, setCount] = useState<number>(-1);

    const uid = user?.uid;

    const getAwards = useCallback(async (): Promise<IResponseData> => {
        const getter = httpsCallable(functions, CLOUD_FUNCTIONS.getUserSway);
        return getter({ uid: uid, locale: locale })
            .then((response: firebase.default.functions.HttpsCallableResult) => {
                return response.data;
            })
            .catch(handleError);
    }, [uid, locale, setCount]);

    useEffect(() => {
        makeCancellable(getAwards(), () => {
            logDev("Cancelled useAwardCount getAwards");
        })
            .then((data: IResponseData) => {
                if (type === AWARD_TYPES.Vote) {
                    setCount(data.userSway.countBillsVotedOn);
                } else if (type === AWARD_TYPES.Invite) {
                    setCount(data.userSway.countInvitesSent);
                } else if (type === AWARD_TYPES.BillShare) {
                    setCount(data.userSway.countAllBillShares);
                } else if (type === AWARD_TYPES.Sway) {
                    setCount(
                        Object.keys(data).reduce((sum: number, key: string) => {
                            if (key.includes("count")) {
                                return sum + data[key];
                            }
                            return sum;
                        }, 0),
                    );
                } else {
                    console.error(`Award type - ${type} - has no data.`);
                }
            })
            .catch(handleError);
    }, [getAwards]);

    return count;
};
