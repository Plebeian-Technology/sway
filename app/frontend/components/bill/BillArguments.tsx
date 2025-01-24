/** @format */
import { IS_MOBILE_PHONE, Support } from "app/frontend/sway_constants";
import { get, isEmpty } from "lodash";
import { useCallback, useMemo, useState } from "react";
import { sway } from "sway";
import BillArgumentsOrganization from "./BillArgumentsOrganization";
import BillSummaryModal from "./BillSummaryModal";

interface IProps {
    bill: sway.IBill;
    bill_organizations: sway.IBillOrganization[];
}

const BillArguments: React.FC<IProps> = ({ bill, bill_organizations }) => {
    const [selectedOrganization, setSelectedOrganization] = useState<sway.IBillOrganizationBase | undefined>();
    const [supportSelected, setSupportSelected] = useState<number>(0);
    const [opposeSelected, setOpposeSelected] = useState<number>(0);

    const organizationPositions = useMemo(
        () =>
            (bill_organizations || [])
                .map((o) => {
                    const position = o.positions.find((p) => p.billId === bill.id);
                    return {
                        bill_organization: o,
                        ...position,
                    };
                })
                .filter((o) => !!o?.support && !!o.summary),
        [bill_organizations, bill],
    ) as (sway.IBillOrganizationPosition & { bill_organization: sway.IBillOrganization })[];

    const supportingOrgs = useMemo(
        () => organizationPositions.filter((o) => o.support === Support.For),
        [organizationPositions],
    );
    const opposingOrgs = useMemo(
        () => organizationPositions.filter((o) => o.support === Support.Against),
        [organizationPositions],
    );

    const mapper = useCallback(
        (
            organizationPosition: sway.IBillOrganizationPosition & { bill_organization: sway.IBillOrganization },
            index: number,
        ) => {
            return (
                <BillArgumentsOrganization
                    key={`${organizationPosition.bill_organization.name}-${index}`}
                    organizationPosition={organizationPosition}
                    index={index}
                    supportSelected={supportSelected}
                    opposeSelected={opposeSelected}
                    setSupportSelected={setSupportSelected}
                    setOpposeSelected={setOpposeSelected}
                />
            );
        },
        [opposeSelected, supportSelected],
    );

    const renderOrgs = useCallback(
        (
            positions: (sway.IBillOrganizationPosition & { bill_organization: sway.IBillOrganization })[],
            title: string,
        ) => (
            <div className="col">
                <span className="bold">{title}</span>
                <div className="row g-0">{isEmpty(positions) ? "None" : positions.map(mapper)}</div>
            </div>
        ),
        [mapper],
    );

    const renderOrgSummary = useCallback(
        (bill_organization: sway.IBillOrganization, position: sway.IBillOrganizationPosition, title: string) => (
            <div className="col">
                <span className="bold">{title}</span>
                <BillSummaryModal
                    summary={position.summary}
                    bill_organization={bill_organization}
                    selectedOrganization={selectedOrganization}
                    setSelectedOrganization={setSelectedOrganization}
                />
            </div>
        ),
        [selectedOrganization],
    );

    const supportingOrg = useMemo(() => get(supportingOrgs, supportSelected) || [], [supportSelected, supportingOrgs]);
    const opposingOrg = useMemo(() => get(opposingOrgs, opposeSelected) || [], [opposeSelected, opposingOrgs]);

    if (IS_MOBILE_PHONE) {
        return (
            <div className="col">
                <div className="row">
                    <div className="col">
                        {renderOrgs(supportingOrgs, "Supporting Organizations")}
                        {renderOrgSummary(supportingOrg.bill_organization, supportingOrg, "Supporting Argument")}
                    </div>
                </div>
                <div className="row">
                    <div className="col">
                        {renderOrgs(opposingOrgs, "Opposing Organizations")}
                        {renderOrgSummary(opposingOrg.bill_organization, opposingOrg, "Opposing Argument")}
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
                    {renderOrgSummary(supportingOrg.bill_organization, supportingOrg, "Supporting Argument")}
                    {renderOrgSummary(opposingOrg.bill_organization, opposingOrg, "Opposing Argument")}
                </div>
            </div>
        );
    }
};

export default BillArguments;
