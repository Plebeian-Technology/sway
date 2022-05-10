import { sway } from "sway";
import Legislator from "./Legislator";

interface IProps {
    user: sway.IUser | undefined;
}

const LegislatorRoute: React.FC<IProps> = ({ user }) => {
    return <Legislator user={user} />;
};

export default LegislatorRoute;
