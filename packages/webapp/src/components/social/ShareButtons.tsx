import {
    FacebookIcon,
    FacebookShareButton,
    TelegramIcon,
    TelegramShareButton,
    TwitterIcon,
    TwitterShareButton,
    WhatsappIcon,
    WhatsappShareButton,
} from "react-share";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill;
    user: sway.IUser;
}

const ShareButtons: React.FC<IProps> = () => {
    return (
        <div className="share-button-container">
            <p>Increase your sway by encouraging people you know to vote.</p>
            <div>
                <TwitterShareButton
                    url={
                        "I voted on the Sway bill of the week. Will you #sway with me?"
                    }
                    windowWidth={900}
                    windowHeight={900}
                >
                    <TwitterIcon />
                </TwitterShareButton>
                <FacebookShareButton
                    url={"https://app.sway.vote/bill-of-the-week"}
                    quote={
                        "I voted on the Sway bill of the week. Will you sway with me?"
                    }
                    hashtag={"#Sway"}
                    windowWidth={900}
                    windowHeight={900}
                >
                    <FacebookIcon />
                </FacebookShareButton>
                <WhatsappShareButton
                    url={"https://app.sway.vote/bill-of-the-week"}
                    title={
                        "I voted on the Sway bill of the week. Will you sway with me?"
                    }
                    windowWidth={900}
                    windowHeight={900}
                >
                    <WhatsappIcon />
                </WhatsappShareButton>
                <TelegramShareButton
                    url={"https://app.sway.vote/bill-of-the-week"}
                    title={
                        "\nI voted on the Sway bill of the week. Will you sway with me?"
                    }
                    windowWidth={900}
                    windowHeight={900}
                >
                    <TelegramIcon />
                </TelegramShareButton>
            </div>
        </div>
    );
};

export default ShareButtons;
