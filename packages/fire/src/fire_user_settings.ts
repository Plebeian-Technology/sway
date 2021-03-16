/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";

class FireUserSettings extends AbstractFireSway {
    uid: string;

    constructor(
        firestore: any,
        locale: sway.ILocale | sway.IUserLocale | null | undefined,
        firestoreConstructor: any,
        uid: string
    ) {
        super(firestore, locale, firestoreConstructor);
        this.uid = uid;
    }

    private collection = (): fire.TypedCollectionReference<sway.IUserSettings> => {
        return this.firestore.collection(
            Collections.UserSettings
        ) as fire.TypedCollectionReference<sway.IUserSettings>;
    };

    private ref = (): fire.TypedDocumentReference<sway.IUserSettings> | undefined => {
        return this.collection().doc(this.uid);
    };

    private snapshot = async (): Promise<fire.TypedDocumentSnapshot<sway.IUserSettings> | undefined> => {
        const ref = this.ref();
        if (!ref) return;

        return ref.get();
    };

    public where = (
        key:
            | "uid"
            | "notificationFrequency"
            | "notificationType"
            | "hasCheckedSupportFab"
            | "messagingRegistrationToken",
        operator: any,
        value: any
    ): fire.TypedQuery<any> => {
        return this.collection().where(
            key,
            operator,
            value
        ) as fire.TypedQuery<any>;
    };

    public get = async (): Promise<sway.IUserSettings | undefined> => {
        const snap = await this.snapshot();
        if (!snap) return;

        return snap.data() as sway.IUserSettings;
    };

    public create = async (
        data: sway.IUserSettings
    ): Promise<sway.IUserSettings | undefined> => {
        const ref = this.ref();
        if (!ref) return;

        await ref.set(data).catch(console.error);
        return data;
    };

    public update = async (
        data: sway.IUserSettings
    ): Promise<sway.IUserSettings | void> => {
        const ref = this.ref();
        if (!ref) return;
        const current = (await ref.get()).data();

        return ref.update({
            ...current,
            ...data,
        });
    };
}

export default FireUserSettings;
