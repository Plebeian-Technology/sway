import { isAtLargeLegislator } from "app/frontend/sway_utils";
import { useCallback, useMemo, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    legislator: sway.ILegislator;
}

const DEFAULT_AVATAR = "/images/politician.svg";

const LegislatorCardAvatar: React.FC<IProps> = ({ legislator }) => {
    const [avatar, setAvatar] = useState(
        legislator?.photo_url?.startsWith("http") ? legislator.photo_url : DEFAULT_AVATAR,
    );

    const isActive = useMemo(() => (legislator.active ? "" : " - Inactive"), [legislator.active]);

    const handleError = useCallback(() => {
        setAvatar(DEFAULT_AVATAR);
    }, []);
    const subheader = useMemo(
        () =>
            isAtLargeLegislator(legislator.district)
                ? `District - At-Large${isActive}`
                : `District - ${legislator.district.number}${isActive}`,
        [isActive, legislator.district],
    );

    return (
        <div className="col-6 col-sm-4">
            <div className="row">
                <div className="col">
                    <div className="bold">{`${legislator.title} ${legislator.full_name}`}</div>
                    <div>{subheader}</div>
                </div>
            </div>
            <div className="row">
                <div className="col" style={{ maxWidth: 300 }}>
                    <Image
                        thumbnail
                        className="border rounded w-100"
                        aria-label={`${legislator.full_name} avatar`}
                        src={avatar || legislator.photo_url}
                        alt={legislator.full_name}
                        onError={avatar === DEFAULT_AVATAR ? undefined : handleError}
                    />
                </div>
            </div>
        </div>
    );
};

export default LegislatorCardAvatar;
