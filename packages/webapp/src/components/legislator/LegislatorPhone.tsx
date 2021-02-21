import { Tooltip, Typography } from "@material-ui/core";
import { Phone } from "@material-ui/icons";
import React from "react";
import { IS_MOBILE_PHONE, SWAY_COLORS } from "../../utils";

interface IProps {
    phone: string;
    handleCopy: (copy: string) => void;
}

const LegislatorPhone: React.FC<IProps> = ({ phone, handleCopy }) => {
    return (
        <div
            style={{
                justifyContent: IS_MOBILE_PHONE ? "flex-start" : "center",
            }}
            className={
                "legislator-card-sub-card-header legislator-card-copy-group"
            }
        >
            <div
                className={"legislator-card-sub-card-header-item"}
                onClick={() => handleCopy(phone)}
            >
                <Phone style={{ color: SWAY_COLORS.primary }} />
            </div>
            <div
                className={"legislator-card-sub-card-header-item"}
                onClick={() => handleCopy(phone)}
            >
                <Typography variant={"body2"}>{phone}</Typography>
            </div>
            <div className={"legislator-card-row-break"} />
            <Tooltip
                title="Copy Phone"
                placement="right"
                onClick={() => handleCopy(phone)}
            >
                <div className={"legislator-card-sub-card-header-item"}>
                    <img
                        alt={"copy button"}
                        src={"/copy.png"}
                        className={"legislator-card-copy-icon"}
                    />
                </div>
            </Tooltip>
        </div>
    );
};

export default LegislatorPhone;
