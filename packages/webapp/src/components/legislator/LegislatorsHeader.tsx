/** @format */

import { Button } from "@material-ui/core";
import React from "react";
import { sway } from "sway";

interface IProps {
    user: sway.IUser | undefined;
    setLegislators: (
        uid: string | undefined,
        localeName: string | undefined,
        district: number | undefined,
        active: boolean,
    ) => void;
    isActive: boolean;
}

const LegislatorsHeader: React.FC<IProps> = ({
    user,
    setLegislators,
    isActive,
}) => {
    const updateLegislators = (active: boolean) => {
        setLegislators(
            user?.uid,
            user?.locale?.name,
            user?.locale?.district,
            active,
        );
    };

    return (
        <div className={"legislators-list-header"}>
            <Button
                className={`${
                    isActive ? "button selected" : "button not-selected"
                }`}
                onClick={() => updateLegislators(true)}
            >
                Active
            </Button>
            <Button
                className={`${
                    !isActive ? "button selected" : "button not-selected"
                }`}
                onClick={() => updateLegislators(false)}
            >
                Inactive
            </Button>
        </div>
    );
};

export default LegislatorsHeader;
