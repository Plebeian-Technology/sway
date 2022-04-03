/** @format */

import { sway } from "sway";

class AbstractFireSway {
    firestore: any;
    firestoreConstructor: any;
    locale: sway.ILocale | sway.IUserLocale | null | undefined;
    logger?: {
        error: (args: any[]) => void;
        warn: (args: any[]) => void;
        info: (args: any[]) => void;
    };

    constructor(
        firestore: any,
        locale: sway.ILocale | sway.IUserLocale | null | undefined,
        firestoreConstructor: any,
        logger?: {
            error: (args: any[]) => void;
            warn: (args: any[]) => void;
            info: (args: any[]) => void;
        },
    ) {
        this.firestore = firestore;
        this.firestoreConstructor = firestoreConstructor;
        this.locale = locale;
        this.logger = logger;
    }

    public log = (data: any) => {
        if (this.logger) {
            this.logger.info(data);
        } else {
            console.log(data);
        }
    };

    public logError = (data: any) => {
        if (this.logger) {
            this.logger.error(data);
        } else {
            console.error(data);
        }
    };
}

export default AbstractFireSway;
