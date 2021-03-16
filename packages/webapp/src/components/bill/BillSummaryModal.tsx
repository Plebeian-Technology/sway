import { createStyles, makeStyles, Typography } from "@material-ui/core";
import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import { titleize } from "@sway/utils";
import React from "react";
import { sway } from "sway";
import DialogWrapper from "../dialogs/DialogWrapper";
import SwaySvg from "../SwaySvg";
import BillSummary from "./BillSummary";

interface IProps {
    localeName: string | null;
    summary: string;
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

const useStyles = makeStyles(() =>
    createStyles({
        header: {
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
            alignItems: "center",
        },
    }),
);

const BillSummaryModal: React.FC<IProps> = ({
    localeName,
    summary,
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
            return "/sway-us-light.png";
        }
        if (organization.name === "Sway") {
            return "/sway-us-light.png";
        }
        if (!organization.iconPath || !localeName) {
            return "/sway-us-light.png";
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
                            {(organization.name !== "Sway") && (
                                <Typography
                                    component="p"
                                    variant="body1"
                                    color="textPrimary"
                                    style={{ fontWeight: "bold" }}
                                >
                                    {titleize(organization.name)}
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
