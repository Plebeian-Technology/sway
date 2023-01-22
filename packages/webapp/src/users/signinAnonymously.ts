import { RecaptchaVerifier, UserCredential, signInAnonymously } from "firebase/auth";
import { auth } from "../firebase";
import { handleError, IS_TAURI } from "../utils";

export const recaptcha = async () => {
    // NOTE: Avoids CSP issues caused by recaptcha
    // https://github.com/google/recaptcha/issues/107
    // https://stackoverflow.com/questions/39853162/recaptcha-with-content-security-policy

    // if (IS_DEVELOPMENT) return "no_captcha_is_development";

    if (IS_TAURI) {
        return Promise.resolve();
    }

    const recaptchaVerifier = new RecaptchaVerifier(
        "recaptcha",
        {
            size: "invisible",
        },
        auth,
    );

    return recaptchaVerifier
        .render()
        .then(() => {
            recaptchaVerifier
                .verify()
                .then(() => {
                    recaptchaVerifier.clear();
                })
                .catch((error) => {
                    recaptchaVerifier.clear();
                    handleError(error);
                });
        })
        .catch((error) => {
            recaptchaVerifier.clear();
            handleError(error);
        });
};

export const anonymousSignIn = async (): Promise<UserCredential | undefined> => {
    return recaptcha()
        .then(() => signInAnonymously(auth))
        .catch((e) => {
            console.error(e);
            return undefined;
        });
};
