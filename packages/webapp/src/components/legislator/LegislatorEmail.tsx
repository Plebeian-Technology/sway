import { useState } from "react";
import { FiMail } from "react-icons/fi";
import { sway } from "sway";
import ContactLegislatorDialog from "../dialogs/ContactLegislatorDialog";
import LegislatorCardSocialItem from "./LegislatorCardSocialItem";

interface IProps {
    user: sway.IUser;
    locale: sway.ILocale;
    legislator: sway.ILegislator;
    handleCopy: (email: string) => void;
}

const Button = ({ handleOpen }: { handleOpen: () => void }) => {
    return <FiMail onClick={handleOpen} />;
};

const LegislatorEmail: React.FC<IProps> = ({ user, locale, legislator, handleCopy }) => {
    const [open, setOpen] = useState<boolean>(false);

    const { email } = legislator;
    if (!email) return null;

    const handleOpen = () => setOpen(true);
    const handleClose = () => setOpen(false);

    return (
        <>
            <LegislatorCardSocialItem
                title={"Email"}
                text={email}
                handleCopy={handleCopy}
                Icon={() => <Button handleOpen={handleOpen} />}
            />
            <ContactLegislatorDialog
                type={"email"}
                user={user}
                locale={locale}
                legislators={[legislator]}
                open={open}
                handleClose={handleClose}
            />
        </>
    );
};

export default LegislatorEmail;
