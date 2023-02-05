import SwayFireClient from "@sway/fire";
import { useMemo } from "react";
import { firestore, firestoreConstructor } from "../firebase";
import { useLocale_JSON } from "./locales";

export const useSwayFireClient = () => {
    const jLocale = useLocale_JSON();
    return useMemo(
        () => new SwayFireClient(firestore, JSON.parse(jLocale), firestoreConstructor, console),
        [jLocale],
    );
};
