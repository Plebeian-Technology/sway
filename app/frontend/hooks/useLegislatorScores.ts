import { useAxiosGet } from "app/frontend/hooks/useAxios";
import { useMemo } from "react";
import { sway } from "sway";

export const useUserLegislatorScore = (legislator: sway.ILegislator) => {
    const options = useMemo(
        () => ({
            skipInitialRequest: false,
        }),
        [],
    );
    return useAxiosGet<sway.scoring.IUserLegislatorScore>(`/user_legislator_scores/${legislator.id}`, options);
};
