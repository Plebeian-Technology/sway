import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import { getDownloadURL, ref } from "firebase/storage";
import { get } from "lodash";
import React, { useCallback, useEffect, useState } from "react";
import { Image } from "react-bootstrap";
import { sway } from "sway";
import { IS_EMULATE, storage } from "../../firebase";

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
            const avatarBySupport = support ? "/thumbs-up.svg" : "/thumbs-down.svg";

            if (iconPath && localeName) {
                const defaultValue = IS_EMULATE
                    ? avatarBySupport
                    : `${GOOGLE_STATIC_ASSETS_BUCKET}/${localeName}/organizations/${iconPath}?alt=media`;
                const storageRef = ref(
                    storage,
                    `${localeName}/organizations/${iconPath}?alt=media`,
                );
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
        <div className={`col-3 p-2 ${isSelected ? "border-bottom border-2 border-primary" : ""}`}>
            <Image
                alt={organization.name}
                style={{ width: "3em", height: "3em" }}
                src={avatarSrc}
                onClick={handler}
                className="m-auto"
                onError={handleAvatarError}
            />
        </div>
    );
};

export default BillArgumentsOrganization;
