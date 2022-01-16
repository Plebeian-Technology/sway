import { Apple, Google, Twitter } from "@mui/icons-material";
import { EAuthProvider } from "src/constants";

import "../scss/social.css";

const SocialButtons: React.FC<{
    handleSigninWithSocialProvider: (provider: EAuthProvider) => void;
}> = ({ handleSigninWithSocialProvider }) => {
    const sites = [Apple, Google, Twitter];
    const names = [
        EAuthProvider.Apple,
        EAuthProvider.Google,
        EAuthProvider.Twitter,
    ];

    return (
        <ul className="social-icons icon-circle icon-zoom list-unstyled list-inline">
            {sites.map((S, i) => (
                <S
                    key={i}
                    onClick={() => handleSigninWithSocialProvider(names[i])}
                    className={`fa fa-${names[
                        i
                    ].toLowerCase()} pe-auto pointer p-3 mx-3`}
                />
            ))}
        </ul>
    );
};

export default SocialButtons;
