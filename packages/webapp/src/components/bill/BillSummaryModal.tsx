import { Typography } from "@material-ui/core";
import {
    DEFAULT_ORGANIZATION,
    GOOGLE_STATIC_ASSETS_BUCKET,
} from "@sway/constants";
import React from "react";
import { sway } from "sway";
import { isMobilePhone } from "../../utils";
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

const classes = {
    container: "bill-arguments-container",
    subContainer: "bill-arguments-sub-container",
    textContainer: "bill-arguments-text-container",
    iconContainer: "bill-arguments-org-icon-container",
    title: "bill-arguments-text-container-title",
    text: "bill-arguments-text",
};

const BillSummaryModal: React.FC<IProps> = ({
    localeName,
    summary,
    organization,
    selectedOrganization,
    setSelectedOrganization,
}) => {
    const isSelected =
        organization && organization.name === selectedOrganization?.name;

    const handleClick = () => setSelectedOrganization(organization);

    const iconPath = () => {
        if (!organization?.iconPath || !localeName) {
            return `${GOOGLE_STATIC_ASSETS_BUCKET}/${DEFAULT_ORGANIZATION.iconPath}?alt=media`;
        }
        return `${GOOGLE_STATIC_ASSETS_BUCKET}/${localeName}%2Forganizations%2F${organization.iconPath}?alt=media`;
    };

    return (
        <>
            <div className={"brighter-item-hover"} onClick={handleClick}>
                <BillSummary
                    summary={summary}
                    klass={classes.text}
                    cutoff={1}
                    handleClick={handleClick}
                />
            </div>
            {organization && isSelected && (
                <DialogWrapper
                    open={true}
                    setOpen={() => setSelectedOrganization(null)}
                    style={!isMobilePhone ? {} : { margin: 0 }}
                >
                    <div>
                        <span>
                            {organization.iconPath && (
                                <SwaySvg src={iconPath()} />
                            )}
                            <Typography
                                component="p"
                                variant="body1"
                                color="textPrimary"
                                style={{ fontWeight: "bold" }}
                            >
                                {organization.name}
                            </Typography>
                        </span>
                        {summary && <BillSummary summary={summary} />}
                    </div>
                </DialogWrapper>
            )}
        </>
    );
};

export default BillSummaryModal;
