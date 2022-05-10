/** @format */

import { Support } from "@sway/constants";
import { logDev } from "@sway/utils";

import { Button } from "react-bootstrap";
import { FiCheck, FiX } from "react-icons/fi";
import { sway } from "sway";

interface IProps {
    user: sway.IUser | undefined;
    dialog: boolean;
    setDialog: (d: boolean) => void;
    support: sway.TSupport;
    setSupport: (s: sway.TSupport) => void;
}

const VoteButtons: React.FC<IProps> = ({ dialog, setDialog, support, setSupport, user }) => {
    logDev("VoteButtons.support -", support);
    const disabled = dialog || !user?.uid || !user?.isRegistrationComplete;

    const handleVote = (clickedSupport: sway.TSupport) => {
        setDialog(true);
        setSupport(clickedSupport);
    };

    return (
        <div className="row my-2">
            <div className="col">
                <Button
                    className={`w-100 py-3 ${support === Support.For ? "white" : ""}`}
                    disabled={disabled || !!support}
                    variant={support === Support.For ? "success" : "outline-success"}
                    onClick={() => handleVote(Support.For as "for")}
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
                >
                    <FiX />
                    &nbsp;Against
                </Button>
            </div>
        </div>
    );
};

export default VoteButtons;
