/** @format */

import { usePoll } from "@inertiajs/react";
import BillComponent from "app/frontend/components/bill/BillComponent";
import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import { useMemo } from "react";
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

const Bill_: React.FC<IProps> = (props) => {
    const only = useMemo(() => ["bill_score"], []);
    usePoll(15000, { only });
    useScoreSubscription(only);

    return <BillComponent {...props} />;
};

const Bill = Bill_;
export default Bill;
