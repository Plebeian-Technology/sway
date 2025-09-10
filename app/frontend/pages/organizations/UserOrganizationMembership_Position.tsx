import { Link, router } from "@inertiajs/react";
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
    const [isEditing, setIsEditing] = useState(false);
    const toggleEditing = () => setIsEditing(!isEditing);

    const [support, setSupport] = useState<string>(position.support);
    const [summary, setSummary] = useState<string>(position.summary);

    const handleSaveChanges = () => {
        if (!isEditing) return;

        router.put(`/user_organization_positions/${position.id}`, {
            support,
            summary,
        });
        // Implement save logic here, e.g., API call to update position
        setIsEditing(false);
    };

    const title = () => {
        const bill_id = position?.bill.id || position?.bill_id;
        return position?.bill ? (
            <Link className="no-underline-hover text-dark" href={`/bills/${bill_id}`}>
                <b>{position.bill.title}</b>
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
                    aria-label="Default select example"
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
            <Card.Footer>
                {isEditing ? (
                    <div className="row">
                        <div className="col">
                            <Button onClick={() => setIsEditing(false)} variant="danger">
                                Cancel Edit
                            </Button>
                        </div>
                        <div className="col text-end">
                            <Button onClick={handleSaveChanges}>Save Changes</Button>
                        </div>
                    </div>
                ) : (
                    <Button onClick={toggleEditing}>Edit Position</Button>
                )}
            </Card.Footer>
        </Card>
    );
};
export default UserOrganizationMembership_Position;
