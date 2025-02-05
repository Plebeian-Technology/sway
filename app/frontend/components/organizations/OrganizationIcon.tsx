import { TOrganizationOption } from "app/frontend/components/admin/creator/types";
import { SWAY_ASSETS_BUCKET_BASE_URL } from "app/frontend/sway_constants/google_cloud_storage";

import { useCallback, useMemo, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    organization?: sway.IOrganizationBase | TOrganizationOption;
    maxWidth?: number;
}

const DEFAULT_ICON_PATH = "/images/sway-us-light.png";

const OrganizationIcon: React.FC<IProps> = ({ organization, maxWidth }) => {
    const [isError, setError] = useState<boolean>(false);

    const icon: string = useMemo(() => {
        if (!organization) {
            return DEFAULT_ICON_PATH;
        } else if ("icon_path" in organization) {
            return organization.icon_path || DEFAULT_ICON_PATH;
        } else if ("iconPath" in organization) {
            return organization.iconPath || DEFAULT_ICON_PATH;
        } else {
            return DEFAULT_ICON_PATH;
        }
    }, [organization]) as string;

    const name: string = useMemo(() => {
        if (!organization) {
            return "<No Name>";
        } else if ("label" in organization) {
            return organization.label;
        } else if ("name" in organization) {
            return organization.name;
        } else {
            return "<No Name>";
        }
    }, [organization]) as string;

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
                <div>{name}</div>
            </div>
        );
    }

    return (
        <div className="col">
            <Image
                alt={name}
                src={src}
                style={{
                    maxWidth: maxWidth ? `${maxWidth}px` : "150px",
                    maxHeight: maxWidth ? `${maxWidth}px` : "150px",
                    width: "150px",
                    height: "150px",
                }}
                className="m-auto"
                onError={handleError}
                decoding="sync"
            />
            <p className="bold mt-2">{name}</p>
        </div>
    );
};

export default OrganizationIcon;
