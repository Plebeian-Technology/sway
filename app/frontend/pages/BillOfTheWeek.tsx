/** @format */



import BillComponent from "app/frontend/components/bill/BillComponent";
import { sway } from "sway";
import LocaleSelector from "../components/user/LocaleSelector";

interface IProps {
    bill: sway.IBill,
    userVote?: sway.IUserVote
}

const BillOfTheWeek: React.FC<IProps> = (props) => {
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

export default BillOfTheWeek;
