/** @format */

import { usePoll } from "@inertiajs/react";
import BillComponent from "app/frontend/components/bill/BillComponent";
import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill;
    sponsor: sway.ILegislator;
    locale: sway.ISwayLocale;
    organizations: sway.IOrganization[];
    legislator_votes: sway.ILegislatorVote[];
    user_vote?: sway.IUserVote;
    bill_score?: sway.IBillScore;
}

const POLLING_PROPS = ["bill_score"];

const Bill_: React.FC<IProps> = (props) => {
    usePoll(15000, { only: POLLING_PROPS });
    const isAwaitingScoreUpdate = useScoreSubscription(POLLING_PROPS);

    return <BillComponent {...props} isAwaitingScoreUpdate={isAwaitingScoreUpdate} />;
};

const Bill = Bill_;
export default Bill;
