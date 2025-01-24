import { TOrganizationOption } from "app/frontend/components/admin/creator/types";
import { SWAY_ASSETS_BUCKET_BASE_URL } from "app/frontend/sway_constants/google_cloud_storage";

import { useCallback, useMemo, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    bill_organization: sway.IBillOrganization | TOrganizationOption | undefined;
    maxWidth?: number;
}

const DEFAULT_ICON_PATH = "/images/sway-us-light.png";

const OrganizationIcon: React.FC<IProps> = ({ bill_organization, maxWidth }) => {
    const [isError, setError] = useState<boolean>(false);

    const icon = useMemo(() => {
        if (!bill_organization) {
            return DEFAULT_ICON_PATH;
        } else if ("icon_path" in bill_organization) {
            return bill_organization.icon_path || DEFAULT_ICON_PATH;
        } else if ("iconPath" in bill_organization) {
            return bill_organization.iconPath || DEFAULT_ICON_PATH;
        } else {
            return DEFAULT_ICON_PATH;
        }
    }, [bill_organization]);

    const name = useMemo(() => {
        if (!bill_organization) {
            return "<No Name>";
        } else if ("label" in bill_organization) {
            return bill_organization.label;
        } else if ("name" in bill_organization) {
            return bill_organization.name;
        } else {
            return "<No Name>";
        }
    }, [bill_organization]);

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
                alt={"an icon for an organization"}
                src={src}
                style={{ maxWidth: maxWidth || 300 }}
                className="m-auto"
                onError={handleError}
                decoding="sync"
            />
            <div>{name}</div>
        </div>
    );
};

export default OrganizationIcon;
