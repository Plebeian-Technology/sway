/** @format */
import { isEmptyObject } from "app/frontend/sway_utils";
import { get } from "lodash";
import { useMemo, useState } from "react";
import { sway } from "sway";
import BillArgumentsOrganization from "./BillArgumentsOrganization";
import BillSummaryModal from "./BillSummaryModal";
import { IS_MOBILE_PHONE } from "app/frontend/sway_constants";

interface IProps {
    localeName: string | null | undefined;
    bill: sway.IBill;
    organizations: sway.IOrganization[] | undefined;
}

const BillArguments: React.FC<IProps> = ({ bill, organizations, localeName }) => {
    const [selectedOrganization, setSelectedOrganization] = useState<sway.IOrganization | null>(
        null,
    );
    const [supportSelected, setSupportSelected] = useState<number>(0);
    const [opposeSelected, setOpposeSelected] = useState<number>(0);
    const billExternalId = bill.externalId;

    const supportingOrgs = useMemo(
        () =>
            organizations
                ? organizations.filter((org: sway.IOrganization) => {
                      const position = org.positions[billExternalId];
                      if (!position) return false;
                      return position.support;
                  })
                : [],
        [organizations, billExternalId],
    );
    const opposingOrgs = useMemo(
        () =>
            organizations
                ? organizations.filter((org: sway.IOrganization) => {
                      const position = org.positions[billExternalId];
                      if (!position) return false;
                      return !position.support;
                  })
                : [],
        [organizations, billExternalId],
    );

    const mapOrgs = (orgs: sway.IOrganization[]) => {
        return (
            orgs &&
            orgs.map((org: sway.IOrganization, index: number) => {
                return (
                    <BillArgumentsOrganization
                        key={`${org.name}-${index}`}
                        localeName={localeName}
                        billExternalId={billExternalId}
                        organization={org}
                        index={index}
                        supportSelected={supportSelected}
                        opposeSelected={opposeSelected}
                        setSupportSelected={setSupportSelected}
                        setOpposeSelected={setOpposeSelected}
                    />
                );
            })
        );
    };

    const renderOrgs = (orgs: sway.IOrganization[], title: string) => (
        <div className="col">
            <span className="bold">{title}</span>
            <div className="row g-0">{isEmptyObject(orgs) ? "None" : mapOrgs(orgs)}</div>
        </div>
    );

    const renderOrgSummary = (org: sway.IOrganization | null, title: string) => (
        <div className="col">
            <span className="bold">{title}</span>
            <BillSummaryModal
                localeName={localeName}
                summary={get(org, `positions.${billExternalId}.summary`) || ""}
                billExternalId={billExternalId}
                organization={org}
                selectedOrganization={selectedOrganization}
                setSelectedOrganization={setSelectedOrganization}
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
