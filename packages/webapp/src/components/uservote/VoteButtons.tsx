/** @format */

import { Support } from "@sway/constants";
import { logDev } from "@sway/utils";

import { Button } from "react-bootstrap";
import { FiCheck, FiX } from "react-icons/fi";
import { sway } from "sway";
import { useFirebaseUser } from "../../hooks";
import { useEmailVerification } from "../../hooks/useEmailVerification";
import { handleError } from "../../utils";

interface IProps {
    user: sway.IUser | undefined;
    dialog: boolean;
    setDialog: (d: boolean) => void;
    support: sway.TSupport;
    setSupport: (s: sway.TSupport) => void;
}

const VoteButtons: React.FC<IProps> = ({ dialog, setDialog, support, setSupport, user }) => {
    logDev("VoteButtons.support -", support);
    const [firebaseUser] = useFirebaseUser();
    const { sendEmailVerification } = useEmailVerification();
    const disabled =
        !user?.isEmailVerified || dialog || !user?.uid || !user?.isRegistrationComplete;

    const handleVote = (clickedSupport: sway.TSupport) => {
        setDialog(true);
        setSupport(clickedSupport);
    };

    const handleResendActivationEmail = () => {
        if (!firebaseUser) return;

        sendEmailVerification(firebaseUser).catch(handleError);
    };

    return (
        <div className="row my-2">
            <div className="col">
                {!user?.isEmailVerified && (
                    <div className="row">
                        <div className="col-xl-4 col-2">&nbsp;</div>
                        <div className="col-xl-4 col-8 text-center mb-2">
                            <Button variant="info" onClick={handleResendActivationEmail}>
                                Verify email to start voting!
                            </Button>
                        </div>
                        <div className="col-xl-4 col-2">&nbsp;</div>
                    </div>
                )}
                <div className="row">
                    <div className="col">
                        <Button
                            className={`w-100 py-3 ${support === Support.For ? "white" : ""}`}
                            disabled={disabled || !!support}
                            variant={support === Support.For ? "success" : "outline-success"}
                            onClick={() => handleVote(Support.For as "for")}
                            style={{ opacity: "70%" }}
                        >
                            <FiCheck />
                            &nbsp;For
                        </Button>
                    </div>
                    <div className="col">
                        <Button
                            className={`w-100 py-3 ${support === Support.Against ? "white" : ""}`}
                            disabled={disabled || !!support}
                            variant={support === Support.Against ? "danger" : "outline-danger"}
                            onClick={() => handleVote(Support.Against as "against")}
                            style={{ opacity: "70%" }}
                        >
                            <FiX />
                            &nbsp;Against
                        </Button>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default VoteButtons;
