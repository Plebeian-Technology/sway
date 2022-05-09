import { GITHUB_LINK, TWITTER_LINK } from "@sway/constants";
import { FiGithub, FiTwitter } from "react-icons/fi";

const SocialIconsList = () => (
    <div className="row w-100 ps-3 fs-4 text-muted pb-3">
        <span className="col-2" onClick={() => window.open(TWITTER_LINK)}>
            <FiTwitter />
        </span>
        <span className="col-2" onClick={() => window.open(GITHUB_LINK)}>
            <FiGithub />
        </span>
    </div>
);

export default SocialIconsList;
