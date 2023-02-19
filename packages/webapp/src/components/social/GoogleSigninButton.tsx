import { useCallback } from "react";
import { EProvider } from "../../hooks/useSignIn";
import "../../scss/google-signin.scss";

interface IProps {
    disabled: boolean;
    setLoading: React.Dispatch<React.SetStateAction<boolean>>;
    onClick: (provider: EProvider) => void;
}

const GoogleSigninButton: React.FC<IProps> = ({ onClick, disabled, setLoading }) => {
    const handleClick = useCallback(
        (e: React.MouseEvent<HTMLButtonElement>) => {
            e.preventDefault();
            if (disabled) return;

            setLoading(true);
            onClick(EProvider.Google);
        },
        [onClick, disabled, setLoading],
    );

    return (
        <button
            type="button"
            className="login-with-google-btn"
            onClick={handleClick}
            disabled={disabled}
        >
            &nbsp;&nbsp;&nbsp;Sign in with Google
        </button>
    );
};

export default GoogleSigninButton;
