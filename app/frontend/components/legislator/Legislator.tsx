/** @format */

import { sway } from "sway";
import LegislatorCard from "./LegislatorCard";

interface IProps {
    legislator: sway.ILegislator;
    locale: sway.ISwayLocale;
}

const Legislator_: React.FC<IProps> = ({ legislator }) => {
    return <LegislatorCard legislator={legislator} inView={true} />;
};

const Legislator = Legislator_;
export default Legislator;
