import { SWAY_ASSETS_BUCKET_BASE_URL } from "app/frontend/sway_constants/google_cloud_storage";

import { useCallback, useMemo, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    organization: sway.IOrganizationBase | undefined;
    maxWidth?: number;
}

const DEFAULT_ICON_PATH = "/images/sway-us-light.png";

const OrganizationIcon: React.FC<IProps> = ({ organization, maxWidth }) => {
    const [isError, setError] = useState<boolean>(false);

    const icon = useMemo(
        () => (organization?.iconPath ? organization.iconPath : DEFAULT_ICON_PATH),
        [organization?.iconPath],
    );
    const src = useMemo(
        () =>
            icon === DEFAULT_ICON_PATH
                ? DEFAULT_ICON_PATH
                : `${SWAY_ASSETS_BUCKET_BASE_URL}${(icon.startsWith("/") ? icon : "/" + icon).replace("//", "/")}`,
        [icon],
    );

    const handleError = useCallback(() => {
        setError(true);
    }, []);

    if (isError) {
        return (
            <div className="col">
                <Image src={DEFAULT_ICON_PATH} alt="" style={{ maxWidth: maxWidth || 300 }} className="m-auto" />
                <div>{organization?.name}</div>
            </div>
        );
    }

    return (
        <div className="col">
            <Image
                alt={""}
                src={src}
                style={{ maxWidth: maxWidth || 300 }}
                className="m-auto"
                onError={handleError}
                fetchPriority="high"
                decoding="sync"
            />
            <div>{organization?.name}</div>
        </div>
    );
};

export default OrganizationIcon;
