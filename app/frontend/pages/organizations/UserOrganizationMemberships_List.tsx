import { Link } from "@inertiajs/react";
import { useUser } from "app/frontend/hooks/users/useUser";
import { ROUTES } from "app/frontend/sway_constants";
import { capitalize } from "lodash";
import { Button, Card, Container, Image } from "react-bootstrap";

const UserOrganizationMemberships_List = () => {
    const user = useUser();

    if (!user?.memberships.length) {
        return <div className="p-3">You are not a member of any organizations.</div>;
    }

    const memberships = user.memberships.map((membership) => {
        return (
            <Card key={membership.id}>
                <Card.Header>
                    <Card.Title className="row align-items-center">
                        <div className="col">
                            {membership.organization.icon_path ? (
                                <Image src={membership.organization.icon_path} className="me-1" />
                            ) : null}
                        </div>
                        <div className="col text-end">
                            <span className="bold">{membership.organization.name}</span>
                        </div>
                    </Card.Title>
                </Card.Header>
                <Card.Body>
                    <Card.Text>
                        Your Role:&nbsp;
                        <span className="bold">{capitalize(membership.role)}</span>
                    </Card.Text>
                    <Link
                        as={Button}
                        href={ROUTES.organizations.memberships.show(membership.organization.id, membership.id)}
                    >
                        View Organization
                    </Link>
                </Card.Body>
            </Card>
        );
    });

    return <Container className="p-3 d-grid gap-4">{memberships}</Container>;
};

export default UserOrganizationMemberships_List;
