import { getStoragePath } from "app/frontend/sway_utils";
import { getDownloadURL, ref } from "firebase/storage";
import { get } from "lodash";
import { useCallback, useEffect, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";
import { storage } from "../../firebase";

interface IProps {
    localeName: string | null | undefined;
    billFirestoreId: string;
    organization: sway.IOrganization;
    supportSelected: number;
    opposeSelected: number;
    setSupportSelected: React.Dispatch<React.SetStateAction<number>>;
    setOpposeSelected: React.Dispatch<React.SetStateAction<number>>;
    index: number;
}

const BillArgumentsOrganization: React.FC<IProps> = ({
    localeName,
    billFirestoreId,
    organization,
    supportSelected,
    opposeSelected,
    setSupportSelected,
    setOpposeSelected,
    index,
}) => {
    const [avatarSrc, setAvatarSrc] = useState<string | undefined>();
    const support = get(organization, `positions.${billFirestoreId}.support`);

    useEffect(() => {
        const getOrganizationAvatarSource = () => {
            const iconPath = organization.iconPath;
            const defaultValue = support ? "/thumbs-up.svg" : "/thumbs-down.svg";

            if (iconPath && localeName) {
                const path = getStoragePath(iconPath, localeName, "organizations");

                const storageRef = ref(storage, path);
                getDownloadURL(storageRef)
                    .then((url) => {
                        setAvatarSrc(url || defaultValue);
                    })
                    .catch((e) => {
                        setAvatarSrc(defaultValue);
                        console.error(e);
                    });
            } else {
                setAvatarSrc(support ? "/thumbs-up.svg" : "/thumbs-down.svg");
            }
        };

        getOrganizationAvatarSource();
    }, [support, localeName, organization.iconPath]);

    const handleAvatarError = useCallback(() => {
        setAvatarSrc(support ? "/thumbs-up.svg" : "/thumbs-down.svg");
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
