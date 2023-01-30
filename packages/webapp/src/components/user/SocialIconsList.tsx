import { GITHUB_LINK, TWITTER_LINK } from "@sway/constants";
import { FiGithub, FiTwitter } from "react-icons/fi";

const SocialIconsList = () => (
    <div className="row w-100 ps-3 fs-4 text-muted text-secondary pb-3">
        <a className="col-2 pointer" href={TWITTER_LINK} target="_blank">
            <FiTwitter />
        </a>
        <a className="col-2 pointer" href={GITHUB_LINK} target="_blank">
            <FiGithub />
        </a>
    </div>
);

export default SocialIconsList;
