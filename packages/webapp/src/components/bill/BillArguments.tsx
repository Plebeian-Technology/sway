/** @format */

import { Typography } from "@material-ui/core";
import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import React from "react";
import { sway } from "sway";
import { isEmptyObject, isNumber, swayBlue } from "../../utils";
import SwaySvg from "../SwaySvg";
import BillSummaryModal from "./BillSummaryModal";

interface IProps {
    localeName: string | null;
    bill: sway.IBill;
    organizations: sway.IOrganization[] | undefined;
}

const classes = {
    container: "bill-arguments-container",
    subContainer: "bill-arguments-sub-container",
    textContainer: "bill-arguments-text-container",
    iconContainer: "bill-arguments-org-icon-container",
    title: "bill-arguments-text-container-title",
    text: "bill-arguments-text",
};

const BillArguments: React.FC<IProps> = ({ bill, organizations, localeName }) => {
    const [
        selectedOrganization,
        setSelectedOrganization,
    ] = React.useState<sway.IOrganization | null>(null);
    const [supportSelected, setSupportSelected] = React.useState<number>(0);
    const [opposeSelected, setOpposeSelected] = React.useState<number>(0);

    const iconStyle = { width: "50px", height: "50px" };
    const billFirestoreId = bill.firestoreId;

    const supportingOrgs = organizations
        ? organizations.filter((org: sway.IOrganization) => {
              const position = org.positions[billFirestoreId];
              if (!position) return false;

              return position.support;
          })
        : [];
    const opposingOrgs = organizations
        ? organizations.filter((org: sway.IOrganization) => {
              const position = org.positions[billFirestoreId];
              if (!position) return false;

              return !position.support;
          })
        : [];

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
                            containerStyle={{
                                padding: "5px",
                                borderBottom: `5px solid ${
                                    selected ? swayBlue : "transparent"
                                }`,
                            }}
                            handleClick={handler}
                        />
                    );
                }
                return (
                    <Typography
                        key={org.name}
                        variant={"body2"}
                        component={"span"}
                        onClick={handler}
                        style={{
                            borderBottom: `5px solid ${
                                selected ? swayBlue : "transparent"
                            }`,
                        }}
                    >
                        {org.name}
                    </Typography>
                );
            })
        );
    };

    const supportingOrg =
        supportingOrgs && isNumber(supportSelected)
            ? supportingOrgs[supportSelected]
            : null;
    const opposingOrg =
        opposingOrgs && isNumber(opposeSelected)
            ? opposingOrgs[opposeSelected]
            : null;


    return (
        <div className={classes.container}>
            <div className={classes.subContainer}>
                <div className={classes.textContainer}>
                    <Typography className={classes.title} component="h4">
                        {"Supporting Organizations"}
                    </Typography>
                    <div className={"bill-arguments-org-icon-container"}>
                        {mapOrgs(supportingOrgs)}
                    </div>
                </div>
                <div className={classes.textContainer}>
                    <Typography className={classes.title} component="h4">
                        {"Opposing Organizations"}
                    </Typography>
                    <div className={classes.iconContainer}>
                        {mapOrgs(opposingOrgs)}
                    </div>
                </div>
            </div>
            <div className={classes.subContainer}>
                <div className={classes.textContainer}>
                    <Typography className={classes.title} component="h4">
                        {"Supporting Argument"}
                    </Typography>

                    <BillSummaryModal
                        localeName={localeName}
                        summary={
                            (!isEmptyObject(organizations) &&
                                supportingOrg &&
                                supportingOrg.positions[billFirestoreId]
                                    ?.summary) ||
                            ""
                        }
                        billFirestoreId={billFirestoreId}
                        organization={supportingOrg}
                        selectedOrganization={selectedOrganization}
                        setSelectedOrganization={setSelectedOrganization}
                    />
                </div>
                <div className={classes.textContainer}>
                    <Typography className={classes.title} component="h4">
                        {"Opposition Argument"}
                    </Typography>
                    <BillSummaryModal
                        localeName={localeName}
                        summary={
                            (!isEmptyObject(organizations) &&
                                opposingOrg &&
                                opposingOrg.positions[billFirestoreId]
                                    ?.summary) ||
                            ""
                        }
                        billFirestoreId={billFirestoreId}
                        organization={opposingOrg}
                        selectedOrganization={selectedOrganization}
                        setSelectedOrganization={setSelectedOrganization}
                    />
                </div>
            </div>
        </div>
    );
};

export default BillArguments;
