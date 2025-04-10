/** @format */

import BillComponent from "app/frontend/components/bill/BillComponent";
import { sway } from "sway";
import LocaleSelector from "../components/user/LocaleSelector";

interface IProps {
    bill: sway.IBill;
    sponsor: sway.ILegislator;
    locale: sway.ISwayLocale;
    organizations: sway.IOrganization[];
    legislator_votes: sway.ILegislatorVote[];
    user_vote?: sway.IUserVote;
}

const BillOfTheWeek_: React.FC<IProps> = (props) => {
    return (
        <div className="col pb-5">
            <div className="row">
                <div className="col">
                    <LocaleSelector />
                </div>
            </div>
            <div className="row pb-5">
                <div className="col pb-5">
                    <BillComponent {...props} />
                </div>
            </div>
        </div>
    );
};

const BillOfTheWeek = BillOfTheWeek_;
export default BillOfTheWeek;
