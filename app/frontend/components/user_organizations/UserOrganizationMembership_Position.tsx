import { Link, router } from "@inertiajs/react";
import { useUserOrganizationMembership_Organization } from "app/frontend/hooks/users/useUserOrganizationMembership";
import { ROUTES } from "app/frontend/sway_constants";
import { useState } from "react";
import { Button, Card, Form } from "react-bootstrap";
import { sway } from "sway";

interface IPositionWithBill extends sway.IOrganizationPosition {
    bill: sway.IBill;
}

interface IProps {
    position: IPositionWithBill;
}

const UserOrganizationMembership_Position = ({ position }: IProps) => {
    const organization = useUserOrganizationMembership_Organization();
    const [isEditing, setIsEditing] = useState(false);
    const toggleEditing = () => setIsEditing(!isEditing);

    const [support, setSupport] = useState<string>(position.support);
    const [summary, setSummary] = useState<string>(position.summary);

    const handleSaveChanges = () => {
        if (!isEditing || !organization?.id) return;

        router.put(ROUTES.organizations.positions.update(organization!.id, position.id), {
            support,
            summary,
        });
        setIsEditing(false);
    };

    const handleDelete = () => {
        if (confirm("Are you sure you want to delete this position?")) {
            router.delete(ROUTES.organizations.positions.destroy(organization!.id, position.id));
        }
    };

    const title = () => {
        const bill_id = position?.bill.id || position?.bill_id;
        return position?.bill ? (
            <Link className="no-underline-hover text-dark" href={`/bills/${bill_id}`}>
                <b>
                    {position.bill.external_id} - {position.bill.title}
                </b>
            </Link>
        ) : (
            <Link
                className="no-underline-hover text-dark"
                href={"#"}
            >{`Unknown Bill with Position ID ${position.id}`}</Link>
        );
    };

    const renderSupport = () => {
        if (isEditing) {
            return (
                <Form.Select
                    name="support"
                    aria-label="Position Support"
                    value={support}
                    onChange={(e) => setSupport(e.target.value)}
                    className="mb-2"
                >
                    <option value="FOR">Support: FOR</option>
                    <option value="AGAINST">Support: AGAINST</option>
                </Form.Select>
            );
        }
        return (
            <Card.Text>
                Support:&nbsp;<span className="bold">{position.support}</span>
            </Card.Text>
        );
    };

    const renderSummary = () => {
        if (isEditing) {
            return (
                <Form.Control
                    as="textarea"
                    rows={10}
                    value={summary}
                    onChange={(e) => {
                        setSummary(e.target.value);
                    }}
                    className="mb-2"
                />
            );
        }
        return <Card.Text>{position.summary}</Card.Text>;
    };

    return (
        <Card key={position.id}>
            <Card.Header>
                <Card.Title>{title()}</Card.Title>
            </Card.Header>
            <Card.Body>
                {renderSupport()}
                {renderSummary()}
            </Card.Body>
            <Card.Footer className="py-3">
                {isEditing ? (
                    <div className="row">
                        <div className="col">
                            <Button onClick={() => setIsEditing(false)} variant="outline-danger">
                                Cancel Edit
                            </Button>
                        </div>
                        <div className="col text-end">
                            <Button onClick={handleSaveChanges}>Save Changes</Button>
                        </div>
                    </div>
                ) : (
                    <div className="row">
                        <div className="col">
                            <Button variant="outline-primary" onClick={toggleEditing}>
                                Edit Position
                            </Button>
                        </div>
                        <div className="col text-end">
                            <Button variant="danger" onClick={handleDelete}>
                                Delete Position
                            </Button>
                        </div>
                    </div>
                )}
            </Card.Footer>
        </Card>
    );
};
export default UserOrganizationMembership_Position;
