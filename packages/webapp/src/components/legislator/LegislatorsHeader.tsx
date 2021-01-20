/** @format */

import { Button } from "@material-ui/core";
import { CONGRESS_LOCALE_NAME, ESwayLevel } from "@sway/constants";
import React from "react";
import { sway } from "sway";
import { titleize } from "../../utils";

interface IProps {
    user: sway.IUser | undefined;
    setLegislators: (
        uid: string | undefined,
        localeName: string | undefined,
        district: number | null | undefined,
        regionCode: string | undefined,
        active: boolean,
        level: ESwayLevel,
    ) => void;
    isActive: boolean;
    level: ESwayLevel;
}

const LegislatorsHeader: React.FC<IProps> = ({
    user,
    setLegislators,
    isActive,
    level,
}) => {
    const updateLegislatorsLevel = (newLevel: ESwayLevel) => {
        setLegislators(
            user?.uid,
            newLevel === ESwayLevel.Congress ? CONGRESS_LOCALE_NAME : user?.locale?.name,
            newLevel === ESwayLevel.Congress
                ? user?.locale?.congressionalDistrict
                : user?.locale?.district,
            user?.locale?._region,
            isActive,
            newLevel,
        );
    };
    // const updateLegislatorsActive = (active: boolean) => {
    //     const congressName =
    //         level === ESwayLevel.Congress && getCongressName();

    //     setLegislators(
    //         user?.uid,
    //         congressName ? congressName : user?.locale?.name,
    //         level === ESwayLevel.Congress
    //             ? user?.locale?.congressionalDistrict
    //             : user?.locale?.district,
    //         active,
    //         level,
    //     );
    // };

    return (
        <div
            style={{
                display: "flex",
                flexDirection: "column",
                width: "100%",
            }}
        >
            <div className={"legislators-list-header"}>
                <Button
                    className={`${
                        level === ESwayLevel.Local ? "button selected" : "button not-selected"
                    }`}
                    onClick={() =>
                        updateLegislatorsLevel(ESwayLevel.Local)
                    }
                >
                    {user?.locale?._city
                        ? titleize(user?.locale?._city)
                        : "Local"}
                </Button>
                <Button
                    className={`${
                        level === ESwayLevel.Congress ? "button selected" : "button not-selected"
                    }`}
                    onClick={() =>
                        updateLegislatorsLevel(ESwayLevel.Congress)
                    }
                >
                    Congress
                </Button>
            </div>
            {/* <div className={"legislators-list-header"}>
                <Button
                    className={`${
                        isActive ? "button selected" : "button not-selected"
                    }`}
                    onClick={() => updateLegislatorsActive(true)}
                >
                    Active
                </Button>
                <Button
                    className={`${
                        !isActive ? "button selected" : "button not-selected"
                    }`}
                    onClick={() => updateLegislatorsActive(false)}
                >
                    Inactive
                </Button>
            </div> */}
        </div>
    );
};

export default LegislatorsHeader;
