/** @format */

import { useEffect, useState } from "react";
import { sway } from "sway";
import LegislatorCard from "./LegislatorCard";
import { useParams } from "react-router";

const Legislator: React.FC = () => {
    const { externalLegislatorId } = useParams<{ externalLegislatorId: string }>();
    const [legislator, setLegislator] = useState<sway.ILegislator | undefined>();

    useEffect(() => {
        // fire.legislators().get(externalLegislatorId).then(setLegislator).catch(console.error);
    }, [externalLegislatorId]);

    if (!legislator) {
        return null;
    } else {
        return <LegislatorCard legislator={legislator} />;
    }
};

export default Legislator;
