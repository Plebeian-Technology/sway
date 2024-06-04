import { SWAY_ASSETS_BUCKET_BASE_URL } from "app/frontend/sway_constants/google_cloud_storage";
import { useCallback, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    organization: sway.IOrganizationBase | undefined;
    maxWidth?: number;
}

const DEFAULT_ICON_PATH = "/images/sway-us-light.png";

const OrganizationIcon: React.FC<IProps> = ({ organization, maxWidth }) => {
    const [icon, setIcon] = useState<string>(organization?.iconPath || DEFAULT_ICON_PATH);

    const handleError = useCallback(() => setIcon(DEFAULT_ICON_PATH), []);

    if (icon === DEFAULT_ICON_PATH) {
        return <Image src={icon} />;
    }
    return (
        <Image
            alt={organization?.name}
            style={{ maxWidth: maxWidth || 300 }}
            src={`${SWAY_ASSETS_BUCKET_BASE_URL}/${icon}`}
            className="m-auto"
            onError={handleError}
        />
    );
};

export default OrganizationIcon;
