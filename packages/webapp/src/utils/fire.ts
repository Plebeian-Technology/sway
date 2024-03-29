/** @format */

import SwayFireClient from "@sway/fire";
import { sway } from "sway";
import { firestore, firestoreConstructor } from "../firebase";

export const swayFireClient = (locale?: sway.ILocale | null): SwayFireClient => {
    return new SwayFireClient(firestore, locale, firestoreConstructor, console);
};
