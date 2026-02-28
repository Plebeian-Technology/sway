import { TOrganizationOption } from "app/frontend/components/admin/creator/types";

import { useCallback, useMemo, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    organization?: sway.IOrganizationBase | TOrganizationOption;
    maxWidth?: number;
}

const IMAGE_STYLE = {
    width: "100%",
    height: "auto",
    display: "block",
    margin: "0px auto",
};

const DEFAULT_ICON_PATH = "/images/sway-us-light.png";

const OrganizationIcon: React.FC<IProps> = ({ organization }) => {
    const [isError, setError] = useState<boolean>(false);

    const icon: string = useMemo(() => {
        if (!organization) {
            return DEFAULT_ICON_PATH;
        } else if ("icon_url" in organization) {
            return organization.icon_url || DEFAULT_ICON_PATH;
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

    const src = useMemo(() => icon, [icon]);

    const handleError = useCallback(() => {
        setError(true);
    }, []);

    if (isError) {
        return (
            <div className="col">
                <Image src={DEFAULT_ICON_PATH} alt="Sway" style={IMAGE_STYLE} />
            </div>
        );
    }

    return (
        <div className="col">
            <Image alt={name} src={src} style={IMAGE_STYLE} onError={handleError} decoding="sync" />
            <span className="bold no-underline text-break">{name}</span>
        </div>
    );
};

export default OrganizationIcon;
