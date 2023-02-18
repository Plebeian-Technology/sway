import { Fragment } from "react";
import { FaApple, FaGoogle } from "react-icons/fa";
import { EProvider } from "../hooks/signin";
import { IS_MOBILE_PHONE } from "../utils";
import AppleSigninButton from "./social/AppleSigninButton";
import GoogleSigninButton from "./social/GoogleSigninButton";

const sites = [FaApple, FaGoogle];
const names = [EProvider.Apple, EProvider.Google];

const SocialButtons: React.FC<{
    handleSigninWithSocialProvider: (provider: EProvider) => void;
}> = ({ handleSigninWithSocialProvider }) => {
    if (IS_MOBILE_PHONE) {
        return (
            <div className="col d-flex flex-column align-items-center">
                {sites.map((S, i) =>
                    EProvider.Apple === names[i] ? (
                        <AppleSigninButton key={i} onClick={handleSigninWithSocialProvider} />
                    ) : (
                        <GoogleSigninButton key={i} onClick={handleSigninWithSocialProvider} />
                    ),
                )}
            </div>
        );
    } else {
        return (
            <div className="row d-flex flex-row justify-content-center">
                {sites.map((S, i) =>
                    EProvider.Apple === names[i] ? (
                        <Fragment key={i}>
                            <AppleSigninButton key={i} onClick={handleSigninWithSocialProvider} />
                            &nbsp; &nbsp;
                        </Fragment>
                    ) : (
                        <GoogleSigninButton key={i} onClick={handleSigninWithSocialProvider} />
                    ),
                )}
            </div>
        );
    }
};

export default SocialButtons;

// (
//     <S
//         key={i}
//         onClick={() => handleSigninWithSocialProvider(names[i])}
//         className={`fa fa-${names[i].toLowerCase()} pe-auto pointer p-3 mx-3`}
//     />
// ))
