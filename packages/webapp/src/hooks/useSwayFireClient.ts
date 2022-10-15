import SwayFireClient from "@sway/fire";
import { firestore } from "../firebase";
import { useLocale } from "./locales";
import { useUser } from "./users";

export const useSwayFireClient = () => {
    const user = useUser();
    const [locale] = useLocale(user);
    return new SwayFireClient(firestore, locale, console);
};
