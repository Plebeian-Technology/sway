import { FaApple, FaGoogle } from "react-icons/fa";
import { EProvider } from "../hooks/signin";
import "../scss/social.css";

const sites = [FaApple, FaGoogle];
const names = [EProvider.Apple, EProvider.Google];

const SocialButtons: React.FC<{
    handleSigninWithSocialProvider: (provider: EProvider) => void;
}> = ({ handleSigninWithSocialProvider }) => {
    return (
        <ul className="social-icons icon-circle icon-zoom list-unstyled list-inline">
            {sites.map((S, i) => (
                <S
                    key={i}
                    onClick={() => handleSigninWithSocialProvider(names[i])}
                    className={`fa fa-${names[i].toLowerCase()} pe-auto pointer p-3 mx-3`}
                />
            ))}
        </ul>
    );
};

export default SocialButtons;
