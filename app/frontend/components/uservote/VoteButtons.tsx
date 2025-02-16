/** @format */

import { useUser } from "app/frontend/hooks/users/useUser";
import { Support } from "app/frontend/sway_constants";
import { notify } from "app/frontend/sway_utils";
import { useCallback } from "react";

import { Button } from "react-bootstrap";
import { FiCheck, FiX } from "react-icons/fi";
import { sway } from "sway";

interface IProps {
    dialog: boolean;
    setDialog: (d: boolean) => void;
    support: sway.TUserSupport | undefined;
    setSupport: (s: sway.TUserSupport) => void;
}

const STYLE = { opacity: "70%" };

const VoteButtons: React.FC<IProps> = ({ dialog, setDialog, support, setSupport }) => {
    const user = useUser();
    const disabled = dialog;

    const handleVote = useCallback(
        (clickedSupport: sway.TUserSupport) => {
            if (!user) {
                notify({
                    level: "error",
                    title: "Sign into your Sway account to vote on this legislation.",
                });
            } else {
                setDialog(true);
                setSupport(clickedSupport);
            }
        },
        [setDialog, setSupport, user],
    );

    const handleFor = useCallback(() => handleVote(Support.For as "FOR"), [handleVote]);
    const handleAgainst = useCallback(() => handleVote(Support.Against as "AGAINST"), [handleVote]);

    return (
        <div className="row my-2">
            <div className="col">
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
