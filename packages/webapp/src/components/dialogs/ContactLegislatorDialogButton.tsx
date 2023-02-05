import { useCallback, useEffect, useMemo, useState } from "react";
import { FiMail } from "react-icons/fi";
import { sway } from "sway";
import { useRepresentatives } from "../../hooks/legislators";
import CenteredDivCol from "../shared/CenteredDivCol";
import ContactLegislatorDialog from "./ContactLegislatorDialog";

interface IProps {
    type: "phone" | "email";
    userVote: sway.IUserVote;
}

const ContactLegislatorDialogButton: React.FC<IProps> = ({ type, userVote }) => {
    const [representatives, getRepresentatives] = useRepresentatives();
    useEffect(() => {
        getRepresentatives(true);
    }, [getRepresentatives]);

    const [open, setOpen] = useState<boolean>(false);
    const handleClose = useCallback(() => setOpen(false), []);

    const children = useMemo(
        () => (
            <>
                <FiMail onClick={() => setOpen(!open)} />
                <ContactLegislatorDialog
                    type={type}
                    userVote={userVote}
                    legislators={representatives}
                    open={open}
                    handleClose={handleClose}
                />
            </>
        ),
        [representatives, userVote, type, open, handleClose],
    );

    if (!representatives) {
        return (
            <CenteredDivCol style={{ width: "100%", height: "100%", zIndex: 10000 }}>
                <FiMail onClick={() => setOpen(false)} />
            </CenteredDivCol>
        );
    }

    if (open) {
        return (
            <CenteredDivCol style={{ width: "100%", height: "100%", zIndex: 10000 }}>
                {children}
            </CenteredDivCol>
        );
    }
    return (
        <CenteredDivCol
            style={{ width: "100%", height: "100%", zIndex: 10000 }}
            onClick={() => setOpen(true)}
        >
            {children}
        </CenteredDivCol>
    );
};

export default ContactLegislatorDialogButton;
