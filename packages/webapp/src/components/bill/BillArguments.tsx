/** @format */

import { createStyles, makeStyles, Typography } from "@material-ui/core";
import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import { get } from "@sway/utils";
import React, { useMemo, useState } from "react";
import { sway } from "sway";
import { IS_MOBILE_PHONE, swayBlue } from "../../utils";
import CenteredDivCol from "../shared/CenteredDivCol";
import FlexColumnDiv from "../shared/FlexColumnDiv";
import FlexRowDiv from "../shared/FlexRowDiv";
import SwaySvg from "../SwaySvg";
import BillSummaryModal from "./BillSummaryModal";

interface IProps {
    localeName: string | null | undefined;
    bill: sway.IBill;
    organizations: sway.IOrganization[] | undefined;
}

const useStyles = makeStyles(() => {
    return createStyles({
        title: {
            fontWeight: 700,
        },
    });
});

const iconStyle = { width: 50, height: 50 };
const withHorizontalMargin = { marginTop: 15, marginLeft: 10, marginRight: 10 };

const BillArguments: React.FC<IProps> = ({
    bill,
    organizations,
    localeName,
}) => {
    const classes = useStyles();
    const [selectedOrganization, setSelectedOrganization] =
        useState<sway.IOrganization | null>(null);
    const [supportSelected, setSupportSelected] = useState<number>(0);
    const [opposeSelected, setOpposeSelected] = useState<number>(0);
    const billFirestoreId = bill.firestoreId;

    const supportingOrgs = useMemo(
        () =>
            organizations
                ? organizations.filter((org: sway.IOrganization) => {
                      const position = org.positions[billFirestoreId];
                      if (!position) return false;

                      return position.support;
                  })
                : [],
        [organizations, billFirestoreId],
    );
    const opposingOrgs = useMemo(
        () =>
            organizations
                ? organizations.filter((org: sway.IOrganization) => {
                      const position = org.positions[billFirestoreId];
                      if (!position) return false;

                      return !position.support;
                  })
                : [],
        [organizations, billFirestoreId],
    );

    const iconContainerStyle = (selected: boolean) => ({
        padding: "5px",
        borderBottom: `5px solid ${selected ? swayBlue : "transparent"}`,
    });

    const mapOrgs = (orgs: sway.IOrganization[]) => {
        return (
            orgs &&
            orgs.map((org: sway.IOrganization, index: number) => {
                const support = org.positions[billFirestoreId].support;
                const handler = support
                    ? () => setSupportSelected(index)
                    : () => setOpposeSelected(index);
                const selected = support
                    ? supportSelected === index
                    : opposeSelected === index;

                if (org.iconPath && localeName) {
                    return (
                        <SwaySvg
                            key={org.name}
                            alt={org.name}
                            src={`${GOOGLE_STATIC_ASSETS_BUCKET}/${localeName}%2Forganizations%2F${org.iconPath}?alt=media`}
                            style={iconStyle}
                            containerStyle={iconContainerStyle(selected)}
                            handleClick={handler}
                        />
                    );
                }
                return (
                    <SwaySvg
                        key={org.name}
                        alt={org.name}
                        src={`${GOOGLE_STATIC_ASSETS_BUCKET}/${
                            support ? "thumbs-up.svg" : "thumbs-down.svg"
                        }`}
                        style={iconStyle}
                        containerStyle={iconContainerStyle(selected)}
                        handleClick={handler}
                    />
                );
            })
        );
    };

    const renderOrgs = (orgs: sway.IOrganization[], title: string) => (
        <CenteredDivCol style={withHorizontalMargin}>
            <Typography className={classes.title} component="h4">
                {title}
            </Typography>
            <FlexRowDiv style={{ justifyContent: "space-between" }}>
                {mapOrgs(orgs)}
            </FlexRowDiv>
        </CenteredDivCol>
    );

    const renderOrgSummary = (
        org: sway.IOrganization | null,
        title: string,
    ) => (
        <CenteredDivCol
            style={{
                ...withHorizontalMargin,
                width: IS_MOBILE_PHONE ? "100%" : "50%",
            }}
        >
            <Typography className={classes.title} component="h4">
                {title}
            </Typography>
            <BillSummaryModal
                localeName={localeName}
                summary={get(org, `positions.${billFirestoreId}.summary`) || ""}
                billFirestoreId={billFirestoreId}
                organization={org}
                selectedOrganization={selectedOrganization}
                setSelectedOrganization={setSelectedOrganization}
            />
        </CenteredDivCol>
    );

    const supportingOrg = get(supportingOrgs, supportSelected);
    const opposingOrg = get(opposingOrgs, opposeSelected);

    if (IS_MOBILE_PHONE) {
        return (
            <FlexColumnDiv
                alignItems="space-between"
                style={withHorizontalMargin}
            >
                <CenteredDivCol>
                    {renderOrgs(supportingOrgs, "Supporting Organizations")}
                    {renderOrgSummary(supportingOrg, "Supporting Argument")}
                </CenteredDivCol>
                <CenteredDivCol>
                    {renderOrgs(opposingOrgs, "Opposing Organizations")}
                    {renderOrgSummary(opposingOrg, "Opposing Argument")}
                </CenteredDivCol>
            </FlexColumnDiv>
        );
    }

    return (
        <FlexColumnDiv alignItems="space-between" style={withHorizontalMargin}>
            <FlexRowDiv justifyContent="space-around">
                {renderOrgs(supportingOrgs, "Supporting Organizations")}
                {renderOrgs(opposingOrgs, "Opposing Organizations")}
            </FlexRowDiv>
            <FlexRowDiv justifyContent="space-around">
                {renderOrgSummary(supportingOrg, "Supporting Argument")}
                {renderOrgSummary(opposingOrg, "Opposing Argument")}
            </FlexRowDiv>
        </FlexColumnDiv>
    );
};

export default BillArguments;
