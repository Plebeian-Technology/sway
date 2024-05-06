import { useAxiosGet } from "app/frontend/hooks/useAxios";
import { sway } from "sway";

export const useUserLegislatorScore = (legislator: sway.ILegislator) => {
    return useAxiosGet<sway.scoring.IUserLegislatorScore>(`/user_legislator_scores/${legislator.id}`, {
        skipInitialRequest: false,
    });
};
