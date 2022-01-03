import { useLocation } from "react-router-dom";
import Slide from "@mui/material/Slide";
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

    return (
        <Slide direction="left" in={true} mountOnEnter unmountOnExit>
            <div>
                <Bill user={user} {...location} />
            </div>
        </Slide>
    );
};

export default BillRoute;
