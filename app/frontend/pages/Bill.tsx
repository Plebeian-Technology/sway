/** @format */

import BillComponent from "app/frontend/components/bill/BillComponent";
import { useEffect } from "react";
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
    useEffect(() => {
        window.scrollTo({ top: 0, left: 0, behavior: "instant" });
    });

    return <BillComponent {...props} />;
};

const Bill = Bill_;
export default Bill;
