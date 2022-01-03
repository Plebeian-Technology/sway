import Slide from "@mui/material/Slide";
import { sway } from "sway";
import Legislator from "./Legislator";

interface IProps {
    user: sway.IUser | undefined;
}

const LegislatorRoute: React.FC<IProps> = ({ user }) => {
    return (
        <Slide direction="left" in={true} mountOnEnter unmountOnExit>
            <div>
                <Legislator user={user} />
            </div>
        </Slide>
    );
};

export default LegislatorRoute;
