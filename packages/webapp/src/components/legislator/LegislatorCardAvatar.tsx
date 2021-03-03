import {
    Avatar,
    createStyles,
    makeStyles,
    Typography,
} from "@material-ui/core";
import React, { useState } from "react";
import { sway } from "sway";
import { IS_MOBILE_PHONE } from "../../utils";

interface IProps {
    legislator: sway.ILegislator;
}

const useStyles = makeStyles(() =>
    createStyles({
        container: {
            margin: 5,
            display: "flex",
            flexDirection: "row",
            justifyContent: "flex-start",
            alignItems: "center",
            textAlign: "left",
            width: IS_MOBILE_PHONE ? "100%" : undefined,
        },
        avatar: {
            marginRight: 10,
        },
    }),
);

const DEFAULT_AVATAR = "/politician.svg";

const LegislatorCardAvatar: React.FC<IProps> = ({ legislator }) => {
    const classes = useStyles();
    const [avatar, setAvatar] = useState(
        legislator.photoURL && legislator.photoURL?.startsWith("https")
            ? legislator.photoURL
            : DEFAULT_AVATAR,
    );

    const isActive = legislator.inOffice || legislator.active ? "Active" : "Inactive";

    const handleError = () => setAvatar(DEFAULT_AVATAR);
    const subheader = () =>
        legislator.district === 0
            ? `At-Large - ${isActive}`
            : `District - ${legislator.district} - ${isActive}`;

    return (
        <div className={classes.container}>
            <div className={classes.avatar}>
                {avatar === DEFAULT_AVATAR ? (
                    <Avatar
                        style={{ width: "3em", height: "3em" }}
                        aria-label={legislator.full_name + " avatar"}
                        src={avatar}
                        alt={legislator.full_name}
                    />
                ) : (
                    <Avatar
                        onError={handleError}
                        style={{ width: "3em", height: "3em" }}
                        aria-label={legislator.full_name}
                        src={avatar}
                        alt={legislator.full_name}
                    />
                )}
            </div>
            <div className={"legislator-card-sub-card-header-item"}>
                <Typography variant={"body1"}>
                    {`${legislator.title} ${legislator.full_name}`}
                </Typography>
                <Typography variant={"body2"}>{subheader()}</Typography>
            </div>
        </div>
    );
};

export default LegislatorCardAvatar;
