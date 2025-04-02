/** @format */
import { IS_MOBILE_PHONE, Support } from "app/frontend/sway_constants";
import { get, isEmpty } from "lodash";
import { useCallback, useMemo, useState } from "react";
import { sway } from "sway";
import BillArgumentsOrganization from "./BillArgumentsOrganization";
import BillSummaryModal from "./BillSummaryModal";
import { Accordion } from "react-bootstrap";

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
                    const position = o.positions.find((p) => p.bill_id === bill.id);
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
        (positions: (sway.IOrganizationPosition & { organization: sway.IOrganization })[], title?: string) => (
            <div className="col">
                {title && <span className="bold">{title}</span>}
                <div className="row">{isEmpty(positions) ? "None" : positions.map(mapper)}</div>
            </div>
        ),
        [mapper],
    );

    const renderOrgSummary = useCallback(
        (organization: sway.IOrganization, position: sway.IOrganizationPosition, title?: string) => (
            <div className="col">
                {title && <span className="bold">{title}</span>}
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
            <Accordion defaultActiveKey="0" alwaysOpen>
                <Accordion.Item eventKey="0">
                    <Accordion.Button className="py-4 bold">Why Support this Bill</Accordion.Button>
                    <Accordion.Body>
                        {supportingOrgs.length ? (
                            <div className="col">
                                {renderOrgs(supportingOrgs)}
                                {renderOrgSummary(supportingOrg.organization, supportingOrg)}
                            </div>
                        ) : (
                            <div className="col">
                                <p>Sway has not yet found any statements of support for this legislation.</p>
                            </div>
                        )}
                    </Accordion.Body>
                </Accordion.Item>
                <Accordion.Item eventKey="1">
                    <Accordion.Button className="py-4 bold">Why Oppose this Bill?</Accordion.Button>
                    <Accordion.Body>
                        {opposingOrgs.length ? (
                            <div className="col">
                                {renderOrgs(opposingOrgs)}
                                {renderOrgSummary(opposingOrg.organization, opposingOrg)}
                            </div>
                        ) : (
                            <div className="col">
                                <p>Sway has not yet found any statements of opposition for this legislation.</p>
                            </div>
                        )}
                    </Accordion.Body>
                </Accordion.Item>
            </Accordion>
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
