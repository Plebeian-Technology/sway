import { useCallback, useState } from "react";
import { FiMail } from "react-icons/fi";
import { sway } from "sway";
import ContactLegislatorDialog from "../dialogs/ContactLegislatorDialog";
import LegislatorCardSocialItem from "./LegislatorCardSocialItem";

interface IProps {
    legislator: sway.ILegislator;
    handleCopy: (email: string) => void;
}

const Button = ({ handleOpen }: { handleOpen: () => void }) => {
    return <FiMail title="Email" onClick={handleOpen} />;
};

const LegislatorEmail: React.FC<IProps> = ({ legislator, handleCopy }) => {
    const [open, setOpen] = useState<boolean>(false);
    const handleOpen = useCallback(() => setOpen(true), []);
    const handleClose = useCallback(() => setOpen(false), []);

    const { email } = legislator;
    if (!email) return null;

    return (
        <>
            <LegislatorCardSocialItem
                title={"Email"}
                text={email}
                handleCopy={handleCopy}
                Icon={<Button handleOpen={handleOpen} />}
            />
            <ContactLegislatorDialog type={"email"} legislator={legislator} open={open} handleClose={handleClose} />
        </>
    );
};

export default LegislatorEmail;
