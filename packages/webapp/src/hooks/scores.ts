import { CLOUD_FUNCTIONS } from "@sway/constants";
import { httpsCallable } from "firebase/functions";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { functions } from "../firebase";
import { useCancellable } from "./cancellable";
import { useUserLocale } from "./locales/useUserLocale";

const getLegislatorUserScore = httpsCallable(functions, CLOUD_FUNCTIONS.getLegislatorUserScores);
const getUserLegislatorScore_CLOUD_FUNCTION = httpsCallable(
    functions,
    CLOUD_FUNCTIONS.getUserLegislatorScore,
);

type TLocaleScoresResult = sway.IAggregatedBillLocaleScores | null | undefined;
export const useLocaleLegislatorScores = ({
    externalId,
    district,
    regionCode,
}: {
    externalId: string;
    district: string;
    regionCode: string;
}): [
    TLocaleScoresResult,
    () => Promise<TLocaleScoresResult>,
    React.Dispatch<React.SetStateAction<TLocaleScoresResult>>,
] => {
    const makeCancellable = useCancellable();
    const userLocale = useUserLocale();
    const [scores, setScores] = useState<TLocaleScoresResult>(undefined);

    const getScores = useCallback(async () => {
        if (!userLocale?.name || !externalId || !district) return null;

        return makeCancellable(
            getLegislatorUserScore({
                locale: userLocale,
                legislator: {
                    externalId,
                    district,
                    regionCode,
                },
            }),
        )
            .then((response: firebase.default.functions.HttpsCallableResult) => {
                if (response.data) {
                    return response.data;
                } else {
                    return null;
                }
            })
            .catch((error) => {
                console.error(error);
                return null;
            });
    }, [userLocale, externalId, district, regionCode, makeCancellable]);

    return [scores, getScores, setScores];
};

type TUserScoresResult = sway.IUserLegislatorScoreV2 | null | undefined;
export const useUserLegislatorScore = ({
    externalId,
    district,
    regionCode,
}: {
    externalId: string;
    district: string;
    regionCode: string;
}): [
    TUserScoresResult,
    () => Promise<TUserScoresResult>,
    React.Dispatch<React.SetStateAction<TUserScoresResult>>,
] => {
    const makeCancellable = useCancellable();
    const userLocale = useUserLocale();
    const [scores, setScores] = useState<TUserScoresResult>(undefined);

    const getScores = useCallback(async () => {
        if (!userLocale?.name || !externalId || !district) return null;

        return makeCancellable(
            getUserLegislatorScore_CLOUD_FUNCTION({
                locale: userLocale,
                legislator: {
                    externalId,
                    district,
                    regionCode,
                },
            }),
        )
            .then((response: firebase.default.functions.HttpsCallableResult) => {
                if (response.data) {
                    return response.data;
                } else {
                    return null;
                }
            })
            .catch((error) => {
                console.error(error);
                return null;
            });
    }, [userLocale, externalId, district, regionCode, makeCancellable]);

    return [scores, getScores, setScores];
};
