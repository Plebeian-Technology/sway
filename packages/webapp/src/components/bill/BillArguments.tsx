/** @format */
import { Avatar } from "@mui/material";
import { GOOGLE_STATIC_ASSETS_BUCKET } from "@sway/constants";
import { get } from "@sway/utils";
import React, { useMemo, useState } from "react";
import { sway } from "sway";
import { IS_MOBILE_PHONE } from "../../utils";
import BillSummaryModal from "./BillSummaryModal";

interface IProps {
    localeName: string | null | undefined;
    bill: sway.IBill;
    organizations: sway.IOrganization[] | undefined;
}

const getCreatedAt = (b: sway.IBill) => {
    if (!b.createdAt) return new Date();
    const seconds = String(b.createdAt.seconds);
    const nanos = String(b.createdAt.nanoseconds).substring(0, 3);
    return new Date(Number(seconds + nanos));
};

const BillArguments: React.FC<IProps> = ({ bill, organizations, localeName }) => {
    const [selectedOrganization, setSelectedOrganization] = useState<sway.IOrganization | null>(
        null,
    );
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

    const getOrganizationAvatarSource = (iconPath: string | undefined, support: boolean) => {
        if (iconPath && localeName) {
            return `${GOOGLE_STATIC_ASSETS_BUCKET}/${localeName}%2Forganizations%2F${iconPath}?alt=media`;
        } else {
            return `${GOOGLE_STATIC_ASSETS_BUCKET}/${
                support ? "thumbs-up.svg" : "thumbs-down.svg"
            }`;
        }
    };

    const mapOrgs = (orgs: sway.IOrganization[]) => {
        return (
            orgs &&
            orgs.map((org: sway.IOrganization, index: number) => {
                const support = org.positions[billFirestoreId].support;
                const handler = support
                    ? () => setSupportSelected(index)
                    : () => setOpposeSelected(index);
                const isSelected = support ? supportSelected === index : opposeSelected === index;

                return (
                    <div
                        key={org.name}
                        className={`col-3 p-2 ${
                            isSelected ? "border-bottom border-2 border-primary" : ""
                        }`}
                    >
                        <Avatar
                            alt={org.name}
                            style={{ width: "3em", height: "3em" }}
                            src={getOrganizationAvatarSource(org.iconPath, support)}
                            onClick={handler}
                            className="m-auto"
                        />
                    </div>
                );
            })
        );
    };

    const renderOrgs = (orgs: sway.IOrganization[], title: string) => (
        <div className="col">
            <span className="bold">{title}</span>
            <div className="row g-0">{mapOrgs(orgs)}</div>
        </div>
    );

    const renderOrgSummary = (org: sway.IOrganization | null, title: string) => (
        <div className="col">
            <span className="bold">{title}</span>
            <BillSummaryModal
                localeName={localeName}
                summary={get(org, `positions.${billFirestoreId}.summary`) || ""}
                billFirestoreId={billFirestoreId}
                organization={org}
                selectedOrganization={selectedOrganization}
                setSelectedOrganization={setSelectedOrganization}
                isUseMarkdown={Boolean(getCreatedAt(bill) < new Date("January 1, 2021"))}
            />
        </div>
    );

    const supportingOrg = get(supportingOrgs, supportSelected);
    const opposingOrg = get(opposingOrgs, opposeSelected);

    if (IS_MOBILE_PHONE) {
        return (
            <div className="col">
                <div className="row">
                    <div className="col">
                        {renderOrgs(supportingOrgs, "Supporting Organizations")}
                        {renderOrgSummary(supportingOrg, "Supporting Argument")}
                    </div>
                </div>
                <div className="row">
                    <div className="col">
                        {renderOrgs(opposingOrgs, "Opposing Organizations")}
                        {renderOrgSummary(opposingOrg, "Opposing Argument")}
                    </div>
                </div>
            </div>
        );
    } else {
        return (
            <div className="col">
                <div className="row">
                    {renderOrgs(supportingOrgs, "Supporting Organizations")}
                    {renderOrgs(opposingOrgs, "Opposing Organizations")}
                </div>
                <div className="row">
                    {renderOrgSummary(supportingOrg, "Supporting Argument")}
                    {renderOrgSummary(opposingOrg, "Opposing Argument")}
                </div>
            </div>
        );
    }
};

export default BillArguments;
