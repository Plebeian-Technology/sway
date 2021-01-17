/** @format */

import { Button } from "@material-ui/core";
import React from "react";
import { sway } from "sway";
import { ESwayLevel } from "@sway/constants";
import { titleize } from "../../utils";

interface IProps {
    level: ESwayLevel;
    setLevel: (level: ESwayLevel) => void;
    user?: sway.IUser;
}

const BillLevelHeader: React.FC<IProps> = ({ level, setLevel, user }) => {
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
                        level === ESwayLevel.Local
                            ? "button selected"
                            : "button not-selected"
                    }`}
                    onClick={() => setLevel(ESwayLevel.Local)}
                >
                    {user?.locale?._city
                        ? titleize(user?.locale?._city)
                        : "Local"}
                </Button>
                <Button
                    className={`${
                        level === ESwayLevel.Congress
                            ? "button selected"
                            : "button not-selected"
                    }`}
                    onClick={() => setLevel(ESwayLevel.Congress)}
                >
                    Congress
                </Button>
            </div>
        </div>
    );
};

export default BillLevelHeader;
