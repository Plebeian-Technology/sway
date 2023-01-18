import { formatPhone } from "@sway/utils";
import { useState } from "react";
import { FiPhone } from "react-icons/fi";
import { sway } from "sway";
import ContactLegislatorDialog from "../dialogs/ContactLegislatorDialog";
import LegislatorCardSocialItem from "./LegislatorCardSocialItem";

interface IProps {
    user: sway.IUser;
    locale: sway.ILocale;
    legislator: sway.ILegislator;
    handleCopy: (phone: string) => void;
}

const Button = ({ handleOpen }: { handleOpen: () => void }) => {
    return <FiPhone onClick={handleOpen} />;
};

const LegislatorPhone: React.FC<IProps> = ({ user, locale, legislator, handleCopy }) => {
    const [open, setOpen] = useState<boolean>(false);

    const { phone } = legislator;
    if (!phone) return null;

    const handleOpen = () => setOpen(true);
    const handleClose = () => setOpen(false);

    return (
        <>
            <LegislatorCardSocialItem
                title={"Phone"}
                text={formatPhone(legislator.phone)}
                handleCopy={handleCopy}
                Icon={() => <Button handleOpen={handleOpen} />}
            />
            <ContactLegislatorDialog
                type="phone"
                user={user}
                locale={locale}
                legislators={[legislator]}
                open={open}
                handleClose={handleClose}
            />
        </>
    );
};

export default LegislatorPhone;
