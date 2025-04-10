import { formatPhone } from "app/frontend/sway_utils/phone";
import { useCallback, useState } from "react";
import { FiPhone } from "react-icons/fi";
import { sway } from "sway";
import ContactLegislatorDialog from "../dialogs/ContactLegislatorDialog";
import LegislatorCardSocialItem from "./LegislatorCardSocialItem";

interface IProps {
    legislator: sway.ILegislator;
    handleCopy: (phone: string) => void;
}

const Button = ({ handleOpen }: { handleOpen: () => void }) => {
    return <FiPhone title="Call" onClick={handleOpen} />;
};

const LegislatorPhone: React.FC<IProps> = ({ legislator, handleCopy }) => {
    const [open, setOpen] = useState<boolean>(false);
    const handleOpen = useCallback(() => setOpen(true), []);
    const handleClose = useCallback(() => setOpen(false), []);

    const { phone } = legislator;
    if (!phone) return null;

    return (
        <>
            <LegislatorCardSocialItem
                title={"Phone"}
                text={formatPhone(legislator.phone)}
                handleCopy={handleCopy}
                Icon={<Button handleOpen={handleOpen} />}
            />
            <ContactLegislatorDialog type="phone" legislator={legislator} open={open} handleClose={handleClose} />
        </>
    );
};

export default LegislatorPhone;
