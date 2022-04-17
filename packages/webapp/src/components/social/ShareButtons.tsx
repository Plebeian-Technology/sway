import { Share } from "@mui/icons-material";
import { Button } from "@mui/material";
import React, { useState } from "react";
import { sway } from "sway";
import ShareDialog from "./ShareDialog";

interface IProps {
    bill: sway.IBill;
    locale: sway.ILocale;
    user: sway.IUser;
    userVote?: sway.IUserVote;
}

const ShareButtons: React.FC<IProps> = (props) => {
    const [isOpen, setOpen] = useState<boolean>(false);

    const handleOpen = () => setOpen(!isOpen);

    return (
        <div className="row">
            <div className="col">
                <div className="row">
                    <div className="col text-center">
                        Increase your sway by encouraging people you know to vote or by engaging
                        your representatives.
                    </div>
                </div>
                <div className="row my-2">
                    <div className="col text-center">
                        <Button variant="outlined" onClick={handleOpen}>
                            <Share />
                            Share
                        </Button>
                    </div>
                </div>
            </div>
            {isOpen && <ShareDialog {...props} handleClose={handleOpen} />}
        </div>
    );
};

export default ShareButtons;
