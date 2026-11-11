// @lat: [[auth-layout-sign-out-overlay-bug#Why the sign-out handler must clear its overlay on failure]]
export const makeSignOutHandler = (logout: () => Promise<unknown>, setIsLoading: (value: boolean) => void) => () => {
    setIsLoading(true);
    logout().catch((err) => {
        console.error(err);
        setIsLoading(false);
    });
};
