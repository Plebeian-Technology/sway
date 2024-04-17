/** @format */

import { Support } from "app/frontend/sway_constants";
import { useCallback } from "react";

import { Button } from "react-bootstrap";
import { FiCheck, FiX } from "react-icons/fi";
import { sway } from "sway";
import { useEmailVerification } from "../../hooks/useEmailVerification";
import { useFirebaseUser } from "../../hooks/users/useFirebaseUser";
import { useIsUserEmailVerified } from "../../hooks/users/useIsUserEmailVerified";
import { useIsUserRegistrationComplete } from "../../hooks/users/useIsUserRegistrationComplete";
import { useUserUid } from "../../hooks/users/useUserUid";
import { handleError } from "../../sway_utils";

interface IProps {
    dialog: boolean;
    setDialog: (d: boolean) => void;
    support: sway.TUserSupport | null;
    setSupport: (s: sway.TUserSupport) => void;
}

const STYLE = { opacity: "70%" };

const VoteButtons: React.FC<IProps> = ({ dialog, setDialog, support, setSupport }) => {
    const [firebaseUser] = useFirebaseUser();
    const uid = useUserUid();
    const isEmailVerified = useIsUserEmailVerified();
    const isRegistrationComplete = useIsUserRegistrationComplete();
    const sendEmailVerification = useEmailVerification();
    const disabled = !isEmailVerified || dialog || !uid || !isRegistrationComplete;

    const handleSendEmailVerification = useCallback(() => {
        sendEmailVerification(firebaseUser).catch(handleError);
    }, [sendEmailVerification, firebaseUser]);

    const handleVote = useCallback(
        (clickedSupport: sway.TUserSupport) => {
            setDialog(true);
            setSupport(clickedSupport);
        },
        [setDialog, setSupport],
    );

    const handleFor = useCallback(() => handleVote(Support.For as "for"), [handleVote]);
    const handleAgainst = useCallback(() => handleVote(Support.Against as "against"), [handleVote]);

    return (
        <div className="row my-2">
            <div className="col">
                {!isEmailVerified && (
                    <div className="row">
                        <div className="col-xl-4 col-2">&nbsp;</div>
                        <div className="col-xl-4 col-8 text-center mb-2">
                            <Button variant="info" onClick={handleSendEmailVerification}>
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
                            onClick={handleFor}
                            style={STYLE}
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
                            onClick={handleAgainst}
                            style={STYLE}
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
