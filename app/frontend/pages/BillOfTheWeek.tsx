/** @format */

import { usePoll } from "@inertiajs/react";
import BillComponent from "app/frontend/components/bill/BillComponent";
import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import { useMemo } from "react";
import { sway } from "sway";
import LocaleSelector from "../components/user/LocaleSelector";

interface IProps {
    bill: sway.IBill;
    sponsor: sway.ILegislator;
    locale: sway.ISwayLocale;
    organizations: sway.IOrganization[];
    legislator_votes: sway.ILegislatorVote[];
    user_vote?: sway.IUserVote;
    bill_score?: sway.IBillScore;
}

const BillOfTheWeek_: React.FC<IProps> = (props) => {
    const only = useMemo(() => ["bill_score"], []);
    usePoll(15000, { only });
    const isAwaitingScoreUpdate = useScoreSubscription(only);

    return (
        <div className="col pb-5">
            <div className="row">
                <div className="col">
                    <LocaleSelector />
                </div>
            </div>
            <div className="row pb-5">
                <div className="col pb-5">
                    <BillComponent {...props} isAwaitingScoreUpdate={isAwaitingScoreUpdate} />
                </div>
            </div>
        </div>
    );
};

const BillOfTheWeek = BillOfTheWeek_;
export default BillOfTheWeek;
