import { CLOUD_FUNCTIONS } from "@sway/constants";
import { logDev } from "@sway/utils";
import { useCallback, useState } from "react";
import { sway } from "sway";
import { functions } from "../firebase";
import { useCancellable } from "./cancellable";

export const useLocaleLegislatorScores = ({
    locale,
    legislator,
}: {
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}): [sway.IAggregatedBillLocaleScores | null | undefined, () => void] => {
    const makeCancellable = useCancellable();

    const [scores, setScores] = useState<
        sway.IAggregatedBillLocaleScores | null | undefined
    >();

    const getter = functions.httpsCallable(
        CLOUD_FUNCTIONS.getLegislatorUserScores,
    );

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
    locale,
    legislator,
}: {
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}): [sway.IUserLegislatorScoreV2 | null | undefined, () => void] => {
    const makeCancellable = useCancellable();

    const [scores, setScores] = useState<
        sway.IUserLegislatorScoreV2 | null | undefined
    >();

    const getter = functions.httpsCallable(
        CLOUD_FUNCTIONS.getUserLegislatorScore,
    );

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
