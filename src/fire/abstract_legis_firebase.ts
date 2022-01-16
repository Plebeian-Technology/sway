/** @format */

import { sway } from "sway";

class AbstractFireSway {
    firestore: any;
    firestoreConstructor: any;
    locale: sway.ILocale | sway.IUserLocale | null | undefined;

    constructor(
        firestore: any,
        locale: sway.ILocale | sway.IUserLocale | null | undefined,
        firestoreConstructor: any,
    ) {
        this.firestore = firestore;
        this.firestoreConstructor = firestoreConstructor;
        this.locale = locale;
    }
}

export default AbstractFireSway;
