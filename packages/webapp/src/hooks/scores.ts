import { CLOUD_FUNCTIONS } from "@sway/constants";
import { httpsCallable } from "firebase/functions";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { functions } from "../firebase";
import { localGet } from "../utils";
import { useCancellable } from "./cancellable";
import { useUserLocale } from "./locales/useUserLocale";

const LOCALE_LEGISLATOR_SCORES_STORAGE_KEY = "@sway/legislators/locale/<locale>/scores";
const USER_LEGISLATOR_SCORES_STORAGE_KEY = "@sway/legislators/user/<locale>/scores";

const getLegislatorUserScore = httpsCallable(functions, CLOUD_FUNCTIONS.getLegislatorUserScores);
const getUserLegislatorScore_CLOUD_FUNCTION = httpsCallable(
    functions,
    CLOUD_FUNCTIONS.getUserLegislatorScore,
);

const getStorageKey = (keyName: string, localeName: string | undefined) => {
    if (!localeName) return;
    return keyName.replace("<locale>", localeName);
};

const getStoredUserLegislatorScores = (keyName: string, localeName: string | undefined) => {
    if (!localeName) return;
    const storageKey = getStorageKey(keyName, localeName);
    if (!storageKey) return;
    const stored = localGet(storageKey);
    return stored ? JSON.parse(stored) : undefined;
};

type TLocaleScoresResult = sway.IAggregatedBillLocaleScores | null | undefined;
export const useLocaleLegislatorScores = ({
    legislator,
}: {
    legislator: sway.ILegislator;
}): [
    TLocaleScoresResult,
    () => Promise<TLocaleScoresResult>,
    React.Dispatch<React.SetStateAction<TLocaleScoresResult>>,
] => {
    const makeCancellable = useCancellable();
    const userLocale = useUserLocale();
    const [scores, setScores] = useState<TLocaleScoresResult>(
        getStoredUserLegislatorScores(LOCALE_LEGISLATOR_SCORES_STORAGE_KEY, userLocale?.name),
    );

    const getScores = useCallback(async () => {
        if (!userLocale?.name || !legislator.externalId || !legislator.district) return null;

        return makeCancellable(
            getLegislatorUserScore({
                locale: userLocale,
                legislator,
            }),
        )
            .then((response: firebase.default.functions.HttpsCallableResult) => {
                if (response.data) {
                    // localSet(
                    //     getStorageKey(
                    //         LOCALE_LEGISLATOR_SCORES_STORAGE_KEY,
                    //         userLocale.name,
                    //     ) as string,
                    //     JSON.stringify(response.data),
                    // );
                    return response.data;
                } else {
                    return null;
                }
            })
            .catch((error) => {
                console.error(error);
                return null;
            });
    }, [userLocale, legislator, makeCancellable]);

    return [scores, getScores, setScores];
};

type TUserScoresResult = sway.IUserLegislatorScoreV2 | null | undefined;
export const useUserLegislatorScore = ({
    legislator,
}: {
    legislator: sway.ILegislator;
}): [
    TUserScoresResult,
    () => Promise<TUserScoresResult>,
    React.Dispatch<React.SetStateAction<TUserScoresResult>>,
] => {
    const makeCancellable = useCancellable();
    const userLocale = useUserLocale();
    const [scores, setScores] = useState<TUserScoresResult>(
        getStoredUserLegislatorScores(USER_LEGISLATOR_SCORES_STORAGE_KEY, userLocale?.name),
    );

    const getScores = useCallback(async () => {
        if (!userLocale?.name || !legislator.externalId || !legislator.district) return null;

        return makeCancellable(
            getUserLegislatorScore_CLOUD_FUNCTION({
                locale: userLocale,
                legislator,
            }),
        )
            .then((response: firebase.default.functions.HttpsCallableResult) => {
                if (response.data) {
                    // localSet(
                    //     getStorageKey(
                    //         USER_LEGISLATOR_SCORES_STORAGE_KEY,
                    //         userLocale.name,
                    //     ) as string,
                    //     JSON.stringify(response.data),
                    // );
                    return response.data;
                } else {
                    return null;
                }
            })
            .catch((error) => {
                console.error(error);
                return null;
            });
    }, [legislator, userLocale, makeCancellable]);

    return [scores, getScores, setScores];
};
