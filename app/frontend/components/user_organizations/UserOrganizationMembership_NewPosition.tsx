import { Form, usePage } from "@inertiajs/react";
import {
    useUserOrganizationMembership_Organization,
    useUserOrganizationMembership_Positions,
} from "app/frontend/hooks/users/useUserOrganizationMembership";
import { ROUTES } from "app/frontend/sway_constants";
import { REACT_SELECT_STYLES } from "app/frontend/sway_utils";
import { useMemo } from "react";
import { Button, FormControl, Modal } from "react-bootstrap";
import Select from "react-select";
import { sway } from "sway";

const SUPPORT_OPTIONS = [
    { value: "FOR", label: "Support: FOR" },
    { value: "AGAINST", label: "Support: AGAINST" },
];

const UserOrganizationMembership_NewPosition = () => {
    const organization = useUserOrganizationMembership_Organization();
    const positions = useUserOrganizationMembership_Positions();
    const bills = usePage().props.bills as sway.IBill[];

    const onHide = () => window.history.back();

    const options = useMemo(
        () =>
            (bills ?? []).map((b) => ({
                label: `${b.external_id} - ${b.title} - Sway Release: ${b.scheduled_release_date_utc || "None"}`,
                value: b.id,
            })),
        [bills],
    );

    if (!organization || !positions.length) return null;

    return (
        <Modal show={true} onHide={onHide} size="lg">
            <Form action={ROUTES.organizations.positions.create(organization.id)} method="post">
                <Modal.Header closeButton>
                    <Modal.Title>Add New Position</Modal.Title>
                </Modal.Header>
                <Modal.Body className="d-grid gap-2">
                    <Select
                        name="bill_id"
                        options={options}
                        styles={REACT_SELECT_STYLES}
                        menuPortalTarget={document.body}
                        menuPosition="fixed"
                        placeholder="Select Bill..."
                    />
                    <Select
                        name="support"
                        aria-label="Position Support"
                        options={SUPPORT_OPTIONS}
                        placeholder="Select Support..."
                        styles={REACT_SELECT_STYLES}
                    />
                    <FormControl name="summary" as="textarea" rows={10} />
                </Modal.Body>
                <Modal.Footer>
                    <Button variant="secondary" onClick={onHide}>
                        Close
                    </Button>
                    <Button variant="primary" type="submit">
                        Save Position
                    </Button>
                </Modal.Footer>
            </Form>
        </Modal>
    );
};

export default UserOrganizationMembership_NewPosition;
