import { getStoragePath } from "app/frontend/sway_utils";
import { get } from "lodash";
import { useCallback, useEffect, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    localeName: string | null | undefined;
    billExternalId: string;
    organization: sway.IOrganization;
    supportSelected: number;
    opposeSelected: number;
    setSupportSelected: React.Dispatch<React.SetStateAction<number>>;
    setOpposeSelected: React.Dispatch<React.SetStateAction<number>>;
    index: number;
}

const BillArgumentsOrganization: React.FC<IProps> = ({
    localeName,
    billExternalId,
    organization,
    supportSelected,
    opposeSelected,
    setSupportSelected,
    setOpposeSelected,
    index,
}) => {
    const [avatarSrc, setAvatarSrc] = useState<string | undefined>();
    const support = get(organization, `positions.${billExternalId}.support`);

    useEffect(() => {
        const getOrganizationAvatarSource = () => {
            const iconPath = organization.iconPath;
            const defaultValue = support ? "/images/thumbs-up.svg" : "/images/thumbs-down.svg";
            setAvatarSrc(defaultValue);
            
            if (iconPath && localeName) {
                const path = getStoragePath(iconPath, localeName, "organizations");

                // const storageRef = ref(storage, path);
                // getDownloadURL(storageRef)
                //     .then((url) => {
                //         setAvatarSrc(url || defaultValue);
                //     })
                //     .catch((e) => {
                //         setAvatarSrc(defaultValue);
                //         console.error(e);
                //     });
            } else {
                setAvatarSrc(support ? "/images/thumbs-up.svg" : "/images/thumbs-down.svg");
            }
        };

        getOrganizationAvatarSource();
    }, [support, localeName, organization.iconPath]);

    const handleAvatarError = useCallback(() => {
        setAvatarSrc(support ? "/images/thumbs-up.svg" : "/images/thumbs-down.svg");
    }, [support]);

    const handler = support ? () => setSupportSelected(index) : () => setOpposeSelected(index);
    const isSelected = support ? supportSelected === index : opposeSelected === index;

    return (
        <div
            className={`col-3 text-center p-2 ${
                isSelected ? "border-bottom border-2 border-primary" : ""
            }`}
        >
            <Image
                alt={organization.name}
                style={{ width: "3em", height: "3em" }}
                src={avatarSrc}
                onClick={handler}
                className="m-auto pointer"
                onError={handleAvatarError}
            />
        </div>
    );
};

export default BillArgumentsOrganization;
