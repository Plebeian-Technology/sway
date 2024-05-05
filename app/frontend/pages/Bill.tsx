/** @format */

import BillComponent from "app/frontend/components/bill/BillComponent";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill,
    userVote?: sway.IUserVote
}

const Bill: React.FC<IProps> = (props) => {
    return <BillComponent {...props} />
};

export default Bill;
