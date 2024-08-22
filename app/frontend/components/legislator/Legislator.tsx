/** @format */

import { sway } from "sway";
import LegislatorCard from "./LegislatorCard";

interface IProps {
    legislator: sway.ILegislator;
    locale: sway.ISwayLocale;
}

const _Legislator: React.FC<IProps> = ({ legislator }) => {
    return <LegislatorCard legislator={legislator} />;
};

const Legislator = _Legislator;
export default Legislator;
