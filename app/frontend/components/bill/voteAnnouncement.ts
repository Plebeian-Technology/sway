import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { sway } from "sway";

interface IArgs {
    voteRecorded?: sway.TUserSupport;
    pendingSupport: sway.TUserSupport | null;
    processing: boolean;
}

// @lat: [[vote-panel-announcements#What a screen reader hears when a vote is cast]]
export const voteAnnouncement = ({ voteRecorded, pendingSupport, processing }: IArgs): string => {
    if (pendingSupport && processing) {
        return PARITY_COPY.vote.processing(pendingSupport as "FOR" | "AGAINST");
    }
    if (voteRecorded) {
        return PARITY_COPY.votePanel.recordedVote(voteRecorded as "FOR" | "AGAINST");
    }
    return "";
};
