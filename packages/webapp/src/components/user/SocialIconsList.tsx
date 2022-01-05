import { Icon } from "@mui/material";
import { GITHUB_LINK, TWITTER_LINK } from "@sway/constants";

const SocialIconsList = () => (
    <div className="row align-items-end h-100 w-100 ps-2">
        <div className="col-2" onClick={() => window.open(TWITTER_LINK)}>
            <Icon fontSize="large" className="h-100">
                <img
                    className="w-100"
                    src={"/icons/twitter.svg"}
                    alt="navigate to Sway twitter"
                />
            </Icon>
        </div>
        <div className="col-2" onClick={() => window.open(GITHUB_LINK)}>
            <Icon fontSize="large" className="h-100">
                <img
                    className="w-100"
                    src={"/icons/github.svg"}
                    alt="navigate to Sway github"
                />
            </Icon>
        </div>
    </div>
);

export default SocialIconsList;
