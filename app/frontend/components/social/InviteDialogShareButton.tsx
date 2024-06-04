import { useCallback, useState } from "react";
import { Button } from "react-bootstrap";
import { FiUserPlus } from "react-icons/fi";
import InviteDialog from "../dialogs/InviteDialog";

const InviteDialogShareButton: React.FC<{
    iconStyle?: React.CSSProperties;
    className?: string;
}> = ({ iconStyle, className }) => {
    const [open, setOpen] = useState<boolean>(false);

    const handleOpen = useCallback(() => setOpen(true), []);
    const handleClose = useCallback((e?: React.MouseEvent<HTMLButtonElement>) => {
        e?.preventDefault();
        e?.stopPropagation();
        setOpen(false);
    }, []);

    return (
        <>
            <Button
                onClick={handleOpen}
                className={`pointer border border-2 rounded text-center ${className || ""}`}
                style={{ width: 64, height: 64, ...iconStyle }}
            >
                <FiUserPlus />
            </Button>
            <InviteDialog open={open} handleClose={handleClose} />
        </>
    );
};

export default InviteDialogShareButton;
