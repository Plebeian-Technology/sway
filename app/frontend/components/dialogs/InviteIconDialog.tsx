import NavLinkButton from "app/frontend/components/drawer/NavLinkButton";
import { Suspense, lazy, useCallback, useState } from "react";
import { Dropdown } from "react-bootstrap";
import { FiUserPlus } from "react-icons/fi";
const InviteDialog = lazy(() => import("./InviteDialog"));

const InviteIconDialog = ({ withText }: { withText?: boolean; iconStyle?: React.CSSProperties }) => {
    const [open, setOpen] = useState<boolean>(false);
    const handleOpenModal = useCallback((e: React.MouseEvent<HTMLElement>) => {
        e.preventDefault();
        e.stopPropagation();

        setOpen(true);
    }, []);
    const handleClose = useCallback((e?: React.MouseEvent<HTMLButtonElement>) => {
        e?.preventDefault();
        e?.stopPropagation();
        setOpen(false);
    }, []);

    return (
        <Dropdown.Item as={NavLinkButton} onClick={handleOpenModal} isSelected={open} disabled={open}>
            <FiUserPlus title="Invite" />
            &nbsp;&nbsp;
            {withText && "Invite Friends"}
            {open && (
                <Suspense fallback={null}>
                    <InviteDialog open={open} handleClose={handleClose} />
                </Suspense>
            )}
        </Dropdown.Item>
    );
};

export default InviteIconDialog;
