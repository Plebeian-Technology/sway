import { CLOUD_FUNCTIONS } from "@sway/constants";
import { logDev } from "@sway/utils";
import { httpsCallable } from "firebase/functions";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { functions } from "../firebase";
import { localGet, localSet } from "../utils";
import { useCancellable } from "./cancellable";

const LOCALE_LEGISLATOR_SCORES_STORAGE_KEY = "@sway/legislators/locale/<locale>/scores";
const USER_LEGISLATOR_SCORES_STORAGE_KEY = "@sway/legislators/user/<locale>/scores";

export const useLocaleLegislatorScores = ({
    locale,
    legislator,
}: {
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}): [sway.IAggregatedBillLocaleScores | null | undefined, () => void] => {
    const storageKey = LOCALE_LEGISLATOR_SCORES_STORAGE_KEY.replace("<locale>", locale.name);
    const stored = localGet(storageKey);

    const makeCancellable = useCancellable();
    const [scores, setScores] = useState<sway.IAggregatedBillLocaleScores | null | undefined>(
        stored ? JSON.parse(stored) : undefined,
    );
    const getter = httpsCallable(functions, CLOUD_FUNCTIONS.getLegislatorUserScores);

    const getScores = useCallback(() => {
        return makeCancellable(
            getter({
                locale,
                legislator,
            }),
            () => {
                logDev("Cancelled getLegislatorUserScores");
                return false;
            },
        )
            .then((response: firebase.default.functions.HttpsCallableResult) => {
                if (!response.data) {
                    setScores(null);
                    return;
                }

                localSet(storageKey, JSON.stringify(response.data));
                setScores(response.data);
                return true;
            })
            .catch((error) => {
                console.error(error);
                setScores(null);
                return false;
            });
    }, []);

    return [scores, getScores];
};

export const useUserLegislatorScore = ({
    locale,
    legislator,
}: {
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}): [sway.IUserLegislatorScoreV2 | null | undefined, () => void] => {
    const storageKey = USER_LEGISLATOR_SCORES_STORAGE_KEY.replace("<locale>", locale.name);
    const stored = localGet(storageKey);

    const makeCancellable = useCancellable();
    const [scores, setScores] = useState<sway.IUserLegislatorScoreV2 | null | undefined>(
        stored ? JSON.parse(stored) : undefined,
    );
    const getter = httpsCallable(functions, CLOUD_FUNCTIONS.getUserLegislatorScore);

    const getScores = useCallback(() => {
        return makeCancellable(
            getter({
                locale,
                legislator,
            }),
            () => {
                logDev("Cancelled getUserLegislatorScore");
            },
        )
            .then((response: firebase.default.functions.HttpsCallableResult) => {
                if (!response.data) {
                    setScores(null);
                    return;
                }

                localSet(storageKey, JSON.stringify(response.data));
                setScores(response.data);
                return true;
            })
            .catch((error) => {
                console.error(error);
                setScores(null);
                return false;
            });
    }, []);

    return [scores, getScores];
};
