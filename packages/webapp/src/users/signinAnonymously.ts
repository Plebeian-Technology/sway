import { IS_DEVELOPMENT } from "@sway/utils";
import { auth, authConstructor } from "../firebase";
import { handleError } from "../utils";

export const recaptcha = async() => {
    // NOTE: Avoids CSP issues caused by recaptcha
    // https://github.com/google/recaptcha/issues/107
    // https://stackoverflow.com/questions/39853162/recaptcha-with-content-security-policy
    if (IS_DEVELOPMENT) return;

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
