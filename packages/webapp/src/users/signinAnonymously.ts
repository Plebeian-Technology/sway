import { auth, authConstructor } from "../firebase";
import { handleError } from "../utils";

export const recaptcha = async () => {
    // NOTE: Avoids CSP issues caused by recaptcha
    // https://github.com/google/recaptcha/issues/107
    // https://stackoverflow.com/questions/39853162/recaptcha-with-content-security-policy

    // if (IS_DEVELOPMENT) return "no_captcha_is_development";

    const recaptchaVerifier = new authConstructor.RecaptchaVerifier(
        "recaptcha",
        {
            size: "invisible",
        },
    );
    return recaptchaVerifier.render().then(() => recaptchaVerifier.verify());
};

export const signInAnonymously = async (): Promise<
    firebase.default.auth.UserCredential | undefined
> => {
    return recaptcha()
        .then((captcha: string) => {
            if (captcha) {
                return auth.signInAnonymously();
            }
            return;
        })
        .catch(handleError);
};
