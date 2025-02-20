import { useCallback, useState } from "react";
import { Button } from "react-bootstrap";
import { FiShare2 } from "react-icons/fi";
import { sway } from "sway";
import ShareDialog from "./ShareDialog";

interface IProps {
    bill: sway.IBill;
    locale: sway.ISwayLocale;
    user_vote?: sway.IUserVote;
}

const ShareButtons: React.FC<IProps> = (props) => {
    const [isOpen, setOpen] = useState<boolean>(false);

    const handleOpen = useCallback(() => setOpen(true), []);
    const handleClose = useCallback(() => setOpen(false), []);

    return (
        <div className="row">
            <div className="col">
                <div className="row">
                    <div className="col text-center">Increase your sway by encouraging people you know to vote.</div>
                </div>
                <div className="row my-2">
                    <div className="col text-center">
                        <Button variant="outline-primary" onClick={handleOpen} size="lg">
                            <FiShare2 />
                            &nbsp;Share
                        </Button>
                    </div>
                </div>
            </div>
            <ShareDialog {...props} isOpen={isOpen} handleClose={handleClose} />
        </div>
    );
};

export default ShareButtons;
