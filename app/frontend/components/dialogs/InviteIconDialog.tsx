import { router } from "@inertiajs/react";
import NavLinkButton from "app/frontend/components/drawer/NavLinkButton";
import { useUser } from "app/frontend/hooks/users/useUser";
import { Suspense, lazy, useCallback, useState } from "react";
import { Dropdown } from "react-bootstrap";
import { FiUserPlus } from "react-icons/fi";
const InviteDialog = lazy(() => import("./InviteDialog"));

const InviteIconDialog = ({ withText }: { withText?: boolean; iconStyle?: React.CSSProperties }) => {
    const user = useUser();

    const [open, setOpen] = useState<boolean>(false);
    const handleOpenModal = useCallback(
        (e: React.MouseEvent<HTMLElement>) => {
            e.preventDefault();
            e.stopPropagation();

            if (!user) {
                router.visit("/");
            } else {
                setOpen(true);
            }
        },
        [user],
    );
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
