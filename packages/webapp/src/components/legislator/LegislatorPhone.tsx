import { Tooltip, Typography } from "@material-ui/core";
import { PhoneOutlined } from "@material-ui/icons";
import React from "react";
import { isMobilePhone } from "../../utils";

interface IProps {
    phone: string;
    handleCopy: (copy: string) => void;
}

const LegislatorPhone: React.FC<IProps> = ({ phone, handleCopy }) => {
    return (
        <div
            style={{
                justifyContent: isMobilePhone ? "flex-start" : "center",
            }}
            className={
                "legislator-card-sub-card-header legislator-card-copy-group"
            }
            onClick={() => handleCopy(phone)}
        >
            <div className={"legislator-card-sub-card-header-item"}>
                <PhoneOutlined />
            </div>
            <div className={"legislator-card-sub-card-header-item"}>
                <Typography variant={"body2"}>{phone}</Typography>
            </div>
            <div className={"legislator-card-row-break"} />
            <Tooltip title="Copy Phone" placement="right">
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
