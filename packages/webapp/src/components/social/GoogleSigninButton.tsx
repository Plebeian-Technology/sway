import { useCallback } from "react";
import { EProvider } from "../../hooks/signin";
import "../../scss/google-signin.scss";

const GoogleSigninButton = ({ onClick }: { onClick: (provider: EProvider) => void }) => {
    const handleClick = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            onClick(EProvider.Google);
        },
        [onClick],
    );

    return (
        <button type="button" className="login-with-google-btn" onClick={handleClick}>
            &nbsp;&nbsp;&nbsp;Sign in with Google
        </button>
    );
};

export default GoogleSigninButton;
