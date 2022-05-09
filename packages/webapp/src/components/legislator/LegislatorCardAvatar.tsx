import { isAtLargeLegislator } from "@sway/utils";
import { useState } from "react";
import { Image } from "react-bootstrap";
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
        <div className="col">
            <div className="row">
                <div className="col">
                    <div className="bold">{`${legislator.title} ${legislator.full_name}`}</div>
                    <div>{subheader()}</div>
                </div>
            </div>
            <div className="row">
                <div className="col">
                    {avatar === DEFAULT_AVATAR ? (
                        <Image
                            roundedCircle
                            thumbnail
                            className="border-0"
                            aria-label={legislator.full_name + " avatar"}
                            src={avatar}
                            alt={legislator.full_name}
                        />
                    ) : (
                        <Image
                            roundedCircle
                            thumbnail
                            className="border-0"
                            onError={handleError}
                            aria-label={legislator.full_name}
                            src={avatar}
                            alt={legislator.full_name}
                        />
                    )}
                </div>
            </div>
        </div>
    );
};

export default LegislatorCardAvatar;
