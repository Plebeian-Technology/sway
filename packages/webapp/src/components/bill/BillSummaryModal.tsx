import { createStyles, makeStyles, Typography } from "@material-ui/core";
import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import React from "react";
import { sway } from "sway";
import swayIcon from "../../assets/sway-us-light.png";
import DialogWrapper from "../dialogs/DialogWrapper";
import SwaySvg from "../SwaySvg";
import BillSummary from "./BillSummary";
import BillSummaryAudio from "./BillSummaryAudio";

interface IProps {
    localeName: string | null;
    summary: string;
    swayAudioBucketPath?: string;
    billFirestoreId: string;
    organization: sway.IOrganization | null;
    selectedOrganization: sway.IOrganization | null;
    setSelectedOrganization: (org: sway.IOrganization | null) => void;
}

const klasses = {
    container: "bill-arguments-container",
    subContainer: "bill-arguments-sub-container",
    textContainer: "bill-arguments-text-container",
    iconContainer: "bill-arguments-org-icon-container",
    title: "bill-arguments-text-container-title",
    text: "bill-arguments-text",
};

const useStyles = makeStyles(() => createStyles({
    header: {
        display: "flex",
        flexDirection: "row",
        justifyContent: "space-between"
    }
}))

const BillSummaryModal: React.FC<IProps> = ({
    localeName,
    summary,
    swayAudioBucketPath,
    organization,
    selectedOrganization,
    setSelectedOrganization,
}) => {
    const classes = useStyles();

    const isSelected =
        organization && organization.name === selectedOrganization?.name;

    const handleClick = () => setSelectedOrganization(organization);

    const iconPath = () => {
        if (!organization) {
            return swayIcon;
        }
        if (organization.name === "Sway") {
            return swayIcon;
        }
        if (!organization.iconPath || !localeName) {
            return swayIcon;
        }
        return `${GOOGLE_STATIC_ASSETS_BUCKET}/${localeName}%2Forganizations%2F${organization.iconPath}?alt=media`;
    };

    return (
        <>
            <div className={"brighter-item-hover"} onClick={handleClick}>
                <BillSummary
                    summary={summary}
                    klass={klasses.text}
                    cutoff={1}
                    handleClick={handleClick}
                />
            </div>
            {organization && isSelected && (
                <DialogWrapper
                    open={true}
                    setOpen={() => setSelectedOrganization(null)}
                    style={{ margin: 0 }}
                >
                    <div>
                        <span className={classes.header}>
                            {organization.iconPath && (
                                <SwaySvg
                                    style={{ width: 50, height: 50 }}
                                    src={iconPath()}
                                    containerStyle={{ marginLeft: 0 }}
                                />
                            )}
                            {swayAudioBucketPath && (
                                <BillSummaryAudio
                                    swayAudioBucketPath={swayAudioBucketPath}
                                />
                            )}
                            {organization.name !== "Sway" && (
                                <Typography
                                    component="p"
                                    variant="body1"
                                    color="textPrimary"
                                    style={{ fontWeight: "bold" }}
                                >
                                    {organization.name}
                                </Typography>
                            )}
                        </span>
                        {summary && <BillSummary summary={summary} />}
                    </div>
                </DialogWrapper>
            )}
        </>
    );
};

export default BillSummaryModal;
