export const logDev = (...args: any[]) => {
    if (process.env.NODE_ENV !== "production") {
        const [message, ...extra] = args;

        if (message instanceof Error) {
            console.error(message);
        } else if (typeof message === "string") {
            console.log(`(dev) ${message}`, ...extra);
        } else {
            console.log("(dev)", message, ...extra);
        }
    }
};
