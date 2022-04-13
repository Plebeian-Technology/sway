import { Avatar, Typography } from "@mui/material";
import { isAtLargeLegislator } from "@sway/utils";
import { useState } from "react";
import { sway } from "sway";

interface IProps {
    legislator: sway.ILegislator;
}

const DEFAULT_AVATAR = "/politician.svg";

const LegislatorCardAvatar: React.FC<IProps> = ({ legislator }) => {
    const [avatar, setAvatar] = useState(
        legislator.photoURL && legislator.photoURL?.startsWith("https")
            ? legislator.photoURL
            : DEFAULT_AVATAR,
    );

    const isActive = legislator.active ? "Active" : "Inactive";

    const handleError = () => setAvatar(DEFAULT_AVATAR);
    const subheader = () =>
        isAtLargeLegislator(legislator)
            ? `At-Large - ${isActive}`
            : `District - ${legislator.district} - ${isActive}`;

    return (
        <div className="ms-2">
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
            <Typography variant="body1">{`${legislator.title} ${legislator.full_name}`}</Typography>
            <Typography variant="body2">{subheader()}</Typography>
        </div>
    );
};

export default LegislatorCardAvatar;
