/** @format */

import BillComponent from "app/frontend/components/bill/BillComponent";
import SetupPage from "app/frontend/components/hoc/SetupPage";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill,
    locale: sway.ISwayLocale;
    userVote?: sway.IUserVote
}

const _Bill: React.FC<IProps> = (props) => {
    return <BillComponent {...props} />
};

const Bill = SetupPage(_Bill)
export default Bill;
