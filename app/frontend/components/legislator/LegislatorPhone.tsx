import { formatPhone } from "app/frontend/sway_utils";
import { useCallback, useMemo, useState } from "react";
import { FiPhone } from "react-icons/fi";
import { sway } from "sway";
import ContactLegislatorDialog from "../dialogs/ContactLegislatorDialog";
import LegislatorCardSocialItem from "./LegislatorCardSocialItem";

interface IProps {
    legislator: sway.ILegislator;
    handleCopy: (phone: string) => void;
}

const Button = ({ handleOpen }: { handleOpen: () => void }) => {
    return <FiPhone onClick={handleOpen} />;
};

const LegislatorPhone: React.FC<IProps> = ({ legislator, handleCopy }) => {
    const [open, setOpen] = useState<boolean>(false);
    const handleOpen = useCallback(() => setOpen(true), []);
    const handleClose = useCallback(() => setOpen(false), []);
    const getIcon = useCallback(() => <Button handleOpen={handleOpen} />, [handleOpen]);
    const legislators = useMemo(() => [legislator], [legislator]);

    const { phone } = legislator;
    if (!phone) return null;

    return (
        <>
            <LegislatorCardSocialItem
                title={"Phone"}
                text={formatPhone(legislator.phone)}
                handleCopy={handleCopy}
                Icon={getIcon}
            />
            <ContactLegislatorDialog
                type="phone"
                legislators={legislators}
                open={open}
                handleClose={handleClose}
            />
        </>
    );
};

export default LegislatorPhone;
