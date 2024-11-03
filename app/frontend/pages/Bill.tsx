/** @format */

import BillComponent from "app/frontend/components/bill/BillComponent";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill;
    sponsor: sway.ILegislator;
    locale: sway.ISwayLocale;
    positions: sway.IOrganizationPosition[];
    legislatorVotes: sway.ILegislatorVote[];
    userVote?: sway.IUserVote;
}

const Bill_: React.FC<IProps> = (props) => {
    return <BillComponent {...props} />;
};

const Bill = Bill_;
export default Bill;
