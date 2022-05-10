import { useLocation } from "react-router-dom";
import { sway } from "sway";
import Bill from "./Bill";

interface IProps {
    user: sway.IUser | undefined;
}

const BillRoute: React.FC<IProps> = ({ user }) => {
    const location = useLocation()?.state as {
        bill: sway.IBill;
        locale: sway.ILocale;
        organizations: sway.IOrganization[];
    };

    return <Bill user={user} {...location} />;
};

export default BillRoute;
