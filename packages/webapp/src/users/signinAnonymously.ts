import { auth, authConstructor } from "../firebase";
import { handleError } from "../utils";

export const recaptcha = () => {
    const recaptchaVerifier = new authConstructor.RecaptchaVerifier(
        "recaptcha",
        {
            size: "invisible",
        },
    );
    return recaptchaVerifier.render().then(() => recaptchaVerifier.verify());
};

export const signInAnonymously = async () => {
    return recaptcha()
        .then(() => auth.signInAnonymously())
        .catch(handleError);
};
