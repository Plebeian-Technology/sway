import { isAtLargeLegislator } from "app/frontend/sway_utils";
import { useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    legislator: sway.ILegislator;
}

const DEFAULT_AVATAR = "/images/politician.svg";

const LegislatorCardAvatar: React.FC<IProps> = ({ legislator }) => {
    const [avatar, setAvatar] = useState(
        legislator?.photoUrl?.startsWith("https") ? legislator.photoUrl : DEFAULT_AVATAR,
    );

    const isActive = legislator.active ? "" : " - Inactive";

    const handleError = () => setAvatar(DEFAULT_AVATAR);
    const subheader = () =>
        isAtLargeLegislator(legislator.district)
            ? `District - At-Large${isActive}`
            : `District - ${legislator.district.number}${isActive}`;

    return (
        <div className="col-6 col-sm-4">
            <div className="row">
                <div className="col">
                    <div className="bold">{`${legislator.title} ${legislator.fullName}`}</div>
                    <div>{subheader()}</div>
                </div>
            </div>
            <div className="row">
                <div className="col" style={{ maxWidth: 300 }}>
                    <Image
                        thumbnail
                        className="border rounded"
                        aria-label={`${legislator.fullName} avatar`}
                        src={avatar || legislator.photoUrl}
                        alt={legislator.fullName}
                        onError={avatar === DEFAULT_AVATAR ? undefined : handleError}
                    />
                </div>
            </div>
        </div>
    );
};

export default LegislatorCardAvatar;
