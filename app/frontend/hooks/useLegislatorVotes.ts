import { useAxiosGet } from "app/frontend/hooks/useAxios";
import { sway } from "sway";

export const useLegislatorVotes = () => {
    return useAxiosGet<sway.ILegislatorVote[]>("/legislator_votes", { skipInitialRequest: true, notifyOnValidationResultFailure: true })
};
