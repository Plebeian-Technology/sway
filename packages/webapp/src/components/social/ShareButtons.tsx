import {
    FacebookIcon,
    FacebookShareButton,
    TelegramIcon,
    TelegramShareButton,
    TwitterIcon,
    TwitterShareButton,
} from "react-share";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill;
    user: sway.IUser;
}

const ShareButtons: React.FC<IProps> = ({ bill, user }) => {
    return (
        <div className="share-button-container">
            <p>Increase your Sway by encouraging your followers to vote.</p>
            <div>
                <TwitterShareButton
                    url={"I voted on the #Sway #BillOfTheWeek"}
                    windowWidth={900}
                    windowHeight={900}
                >
                    <TwitterIcon />
                </TwitterShareButton>
                <FacebookShareButton url={"I vote"}>
                    <FacebookIcon />
                </FacebookShareButton>
                <TelegramShareButton url={"I vote"}>
                    <TelegramIcon />
                </TelegramShareButton>
            </div>
        </div>
    );
};

export default ShareButtons;
