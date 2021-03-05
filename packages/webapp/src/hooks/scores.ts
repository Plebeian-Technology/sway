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
}): [sway.IAggregatedBillLocaleScores | undefined, () => void] => {
    const [scores, setScores] = useState<
        sway.IAggregatedBillLocaleScores | undefined
    >();

    const getter = functions.httpsCallable(
        CLOUD_FUNCTIONS.getLegislatorUserScores,
    );

    const getScores = useCallback(() => {
        getter({
            locale,
            legislator,
        })
            .then(
                (response: firebase.default.functions.HttpsCallableResult) => {
                    if (!response.data) return;

                    setScores(response.data);
                },
            )
            .catch((error) => {
                console.error(error);
                return;
            });
    }, []);

    return [scores, getScores];
};

export const useUserLegislatorScore = ({
    user,
    locale,
    legislator,
}: {
    user: sway.IUser;
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}): [sway.IUserLegislatorScore | undefined, () => void] => {
    const [scores, setScores] = useState<
        sway.IUserLegislatorScore | undefined
    >();

    const getScores = useCallback(() => {
        swayFireClient(locale)
            .userLegislatorScores()
            .get(legislator.externalId, user.uid)
            .then((data) => {
                setScores(data);
            })
            .catch(console.error);
    }, []);

    return [scores, getScores];
};
