import { GITHUB_LINK } from "app/frontend/sway_constants";
import { FiGithub } from "react-icons/fi";

const SocialIconsList = () => (
    <div className="row w-100 fs-4" style={{ position: "fixed", bottom: 20 }}>
        <a className="col-2 col-md-1 pointer" href={GITHUB_LINK} target="_blank">
            <FiGithub />
        </a>
    </div>
);

export default SocialIconsList;
