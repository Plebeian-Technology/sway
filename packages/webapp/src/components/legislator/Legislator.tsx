/** @format */

import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { sway } from "sway";
import { useSwayFireClient } from "../../hooks/useSwayFireClient";
import LegislatorCard from "./LegislatorCard";

const Legislator: React.FC = () => {
    const fire = useSwayFireClient();
    const { externalLegislatorId } = useParams<{ externalLegislatorId: string }>();
    const [legislator, setLegislator] = useState<sway.ILegislator | undefined>();

    useEffect(() => {
        fire.legislators().get(externalLegislatorId).then(setLegislator).catch(console.error);
    }, [fire, externalLegislatorId]);

    if (!legislator) {
        return null;
    } else {
        return <LegislatorCard legislator={legislator} />;
    }
};

export default Legislator;
