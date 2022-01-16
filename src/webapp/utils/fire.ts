/** @format */

import SwayFireClient from "src/fire";
import { sway } from "sway";
import { firestore, firestoreConstructor } from "src/webapp/firebase";

export const swayFireClient = (
    locale?: sway.ILocale | null,
): SwayFireClient => {
    return new SwayFireClient(firestore, locale, firestoreConstructor);
};
