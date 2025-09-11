import { Link, router, usePage } from "@inertiajs/react";
import { IMembership, useUserOrganizationMembership } from "app/frontend/hooks/users/useUserOrganizationMembership";
import { notify } from "app/frontend/sway_utils";
import { formatDateTime } from "app/frontend/sway_utils/datetimes";
import { diffChars } from "diff";
import { useEffect, useRef } from "react";
import { Button, Card } from "react-bootstrap";

function renderDiff(change: IMembership["pending_changes"][number]) {
    const diff = diffChars(change.previous_summary, change.new_summary);
    return (
        <span>
            {diff.map((part, idx) => {
                if (part.added) {
                    return (
                        <span key={idx} style={{ backgroundColor: "#d4f8e8" }}>
                            {part.value}
                        </span>
                    );
                }
                if (part.removed) {
                    return (
                        <span key={idx} style={{ backgroundColor: "#ffe6e6" }}>
                            {part.value}
                        </span>
                    );
                }
                return <span key={idx}>{part.value}</span>;
            })}
        </span>
    );
}

const UserOrganizationMembership_Approval = ({ change }: { change: IMembership["pending_changes"][number] }) => {
    const ref = useRef<HTMLDivElement | null>(null);
    const membership = useUserOrganizationMembership() as IMembership;
    const newPositionId = usePage().props.new_position_id as number | null;

    useEffect(() => {
        if (newPositionId && change.id === newPositionId && ref.current) {
            ref.current.scrollIntoView({ behavior: "smooth", block: "start" });
        }
    }, [change.id, newPositionId]);

    const isOrganizationAdmin = membership?.role === "admin";

    const title = () => {
        const position = membership.positions!.find((p) => p.id === change.organization_bill_position_id);
        const bill_id = position?.bill.id || position?.bill_id;
        return position?.bill ? (
            <Link className="no-underline-hover text-dark" href={`/bills/${bill_id}`}>
                <b>
                    {position.bill.external_id} - {position.bill.title}
                </b>
            </Link>
        ) : (
            <Link href={"#"}>{`Unknown Bill with Position ID ${change.organization_bill_position_id}`}</Link>
        );
    };

    const handleApproval = () => {
        if (change.approved_by_id || membership.role !== "admin") {
            notify({
                level: "error",
                title: "Changes can already be approved by an organization admin.",
            });
            return;
        }
        router.put(`/organizations/${membership.organization.id}/position_changes/${change.id}`);
    };

    return (
        <Card key={change.id} ref={ref}>
            <Card.Header>
                <Card.Title>{title()}</Card.Title>
            </Card.Header>
            <Card.Body>
                <Card.Text>
                    Previous Support: <b>{change.previous_support}</b>
                </Card.Text>
                <Card.Text>
                    New Support: <b>{change.new_support}</b>
                </Card.Text>

                <hr />

                <Card.Text>
                    <b>Diff of Changes:</b>
                    <br />
                    {renderDiff(change)}
                </Card.Text>

                <hr />

                <Card.Text>
                    <b>New Position Summary:</b>
                    <br />
                    {change.new_summary}
                </Card.Text>
                <Card.Text>
                    <b>Previous Position Summary:</b>
                    <br />
                    {change.previous_summary}
                </Card.Text>
            </Card.Body>
            <Card.Footer className="row align-items-center g-0">
                <div className="col">Created On: {formatDateTime(change.created_at)}</div>
                <div className="col text-end">
                    <Button
                        disabled={!!change.approved_by_id || !isOrganizationAdmin}
                        onClick={handleApproval}
                        variant={change.approved_by_id || !isOrganizationAdmin ? "secondary" : "primary"}
                    >
                        {change.approved_by_id
                            ? "Approved"
                            : isOrganizationAdmin
                              ? "Approve Change"
                              : "Pending Approval"}
                    </Button>
                </div>
            </Card.Footer>
        </Card>
    );
};

export default UserOrganizationMembership_Approval;
