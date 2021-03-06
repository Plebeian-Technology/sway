import { CLOUD_FUNCTIONS } from "@sway/constants";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { functions } from "../firebase";
import { swayFireClient } from "../utils";

export const useLocaleLegislatorScores = ({
    locale,
    legislator,
}: {
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}): [sway.IAggregatedBillLocaleScores | null | undefined, () => void] => {
    const [scores, setScores] = useState<
        sway.IAggregatedBillLocaleScores | null | undefined
    >();

    const getter = functions.httpsCallable(
        CLOUD_FUNCTIONS.getLegislatorUserScores,
    );

    const getScores = useCallback(() => {
        return getter({
            locale,
            legislator,
        })
            .then(
                (response: firebase.default.functions.HttpsCallableResult) => {
                    if (!response.data) {
                        setScores(null);
                        return;
                    }

                    setScores(response.data);
                    return true;
                },
            )
            .catch((error) => {
                console.error(error);
                setScores(null);
                return false;
            });
    }, []);

    return [scores, getScores];
};

export const useUserLegislatorScore = ({
    user,
    locale,
    legislator,
}: {
    user: sway.IUser | undefined;
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}): [sway.IUserLegislatorScore | null | undefined, () => void] => {
    const [scores, setScores] = useState<
        sway.IUserLegislatorScore | null | undefined
    >();

    const getScores = useCallback(() => {
        if (!user) return;

        return swayFireClient(locale)
            .userLegislatorScores()
            .get(legislator.externalId, user.uid)
            .then((data) => {
                if (!data) {
                    setScores(null);
                    return;
                }
                setScores(data);
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
