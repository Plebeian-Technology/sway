import { AuthError, sendEmailVerification, User } from "firebase/auth";
import { useCallback } from "react";
import { notify } from "../utils";

export const useEmailVerification = () => {
    return useCallback(async (user: User | null | undefined) => {
        if (user) {
            // * NOTE: The below URL redirects the user from the Firebase confirmation screen to a Sway confirmation screen
            // * The redirect is NOT currently needed since there is a setInterval listener for when the user verifies in SignIn.tsx
            // * August 8, 2022
            // const url = `${window.location.origin}${ROUTES.signin}?${NOTIFY_COMPLETED_REGISTRATION}=1`;
            // return sendEmailVerification(, { url })
            return sendEmailVerification(user)
                .then(() => {
                    notify({
                        level: "success",
                        title: "Activation email sent!",
                        message: `We've sent a verification email to ${user.email}. Please follow the instructions in it to verify your account.`,
                        duration: 7000,
                    });
                    return true;
                })
                .catch((error: AuthError) => {
                    console.error(error);
                    if (error.code === "auth/too-many-requests") {
                        notify({
                            level: "error",
                            title: "Error: Too many activation requests.",
                            message: "Please try again later.",
                        });
                    } else {
                        notify({
                            level: "error",
                            title: "Error sending activation email.",
                            message: "Please try again later.",
                        });
                    }
                    return false;
                });
        } else {
            return false;
        }
    }, []);
};
