/** @format */
import { IS_MOBILE_PHONE, Support } from "app/frontend/sway_constants";
import { get, isEmpty } from "lodash";
import { useCallback, useMemo, useState } from "react";
import { sway } from "sway";
import BillArgumentsOrganization from "./BillArgumentsOrganization";
import BillSummaryModal from "./BillSummaryModal";

interface IProps {
    bill: sway.IBill;
    organizations: sway.IOrganization[];
}

const BillArguments: React.FC<IProps> = ({ bill, organizations }) => {
    const [selectedOrganization, setSelectedOrganization] = useState<sway.IOrganizationBase | undefined>();
    const [supportSelected, setSupportSelected] = useState<number>(0);
    const [opposeSelected, setOpposeSelected] = useState<number>(0);

    const organizationPositions = useMemo(
        () =>
            (organizations || [])
                .map((o) => {
                    const position = o.positions.find((p) => p.billId === bill.id);
                    return {
                        organization: o,
                        ...position,
                    };
                })
                .filter((o) => !!o?.support && !!o.summary),
        [organizations, bill],
    ) as (sway.IOrganizationPosition & { organization: sway.IOrganization })[];

    const supportingOrgs = useMemo(
        () => organizationPositions.filter((o) => o.support === Support.For),
        [organizationPositions],
    );
    const opposingOrgs = useMemo(
        () => organizationPositions.filter((o) => o.support === Support.Against),
        [organizationPositions],
    );

    const mapper = useCallback(
        (organizationPosition: sway.IOrganizationPosition & { organization: sway.IOrganization }, index: number) => {
            return (
                <BillArgumentsOrganization
                    key={`${organizationPosition.organization.name}-${index}`}
                    organizationsCount={
                        organizationPosition.support === Support.For ? supportingOrgs.length : opposingOrgs.length
                    }
                    organizationPosition={organizationPosition}
                    organization={organizationPosition.organization}
                    index={index}
                    supportSelected={supportSelected}
                    opposeSelected={opposeSelected}
                    setSupportSelected={setSupportSelected}
                    setOpposeSelected={setOpposeSelected}
                />
            );
        },
        [opposeSelected, opposingOrgs.length, supportSelected, supportingOrgs.length],
    );

    const renderOrgs = useCallback(
        (positions: (sway.IOrganizationPosition & { organization: sway.IOrganization })[], title: string) => (
            <div className="col">
                <span className="bold">{title}</span>
                <div className="row">{isEmpty(positions) ? "None" : positions.map(mapper)}</div>
            </div>
        ),
        [mapper],
    );

    const renderOrgSummary = useCallback(
        (organization: sway.IOrganization, position: sway.IOrganizationPosition, title: string) => (
            <div className="col">
                <span className="bold">{title}</span>
                <BillSummaryModal
                    summary={position.summary}
                    organization={organization}
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
                {!!supportingOrgs.length && (
                    <div className="row">
                        <div className="col">
                            <div className="row">{renderOrgs(supportingOrgs, "Supporting Organizations")}</div>
                            <div className="row">
                                {renderOrgSummary(supportingOrg.organization, supportingOrg, "Supporting Argument")}
                            </div>
                        </div>
                    </div>
                )}
                {!!opposingOrgs.length && (
                    <div className="row">
                        <div className="col">
                            {renderOrgs(opposingOrgs, "Opposing Organizations")}
                            {renderOrgSummary(opposingOrg.organization, opposingOrg, "Opposing Argument")}
                        </div>
                    </div>
                )}
            </div>
        );
    } else {
        return (
            <div className="col">
                {!!(supportingOrgs.length || opposingOrgs.length) && (
                    <div className="row">
                        {renderOrgs(supportingOrgs, "Supporting Organizations")}
                        {renderOrgs(opposingOrgs, "Opposing Organizations")}
                    </div>
                )}
                {!!(supportingOrg.organization || opposingOrg.organization) && (
                    <div className="row">
                        {renderOrgSummary(supportingOrg.organization, supportingOrg, "Supporting Argument")}
                        {renderOrgSummary(opposingOrg.organization, opposingOrg, "Opposing Argument")}
                    </div>
                )}
            </div>
        );
    }
};

export default BillArguments;
