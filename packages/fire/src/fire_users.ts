/** @format */

import { Collections, DEFAULT_USER_SETTINGS } from "@sway/constants";
import { logDev } from "@sway/utils";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
import FireUserSettings from "./fire_user_settings";
class FireUsers extends AbstractFireSway {
    uid: string;

    constructor(
        firestore: any,
        locale: sway.ILocale | null | undefined,
        firestoreConstructor: any,
        uid: string,
    ) {
        super(firestore, locale, firestoreConstructor);
        this.uid = uid;
    }

    private collection = (): fire.TypedCollectionReference<sway.IUser> => {
        return this.firestore.collection(
            Collections.Users,
        ) as fire.TypedCollectionReference<sway.IUser>;
    };

    private ref = (): fire.TypedDocumentReference<sway.IUser> | undefined => {
        return this.collection().doc(this.uid);
    };

    private snapshot = async (): Promise<
        fire.TypedDocumentSnapshot<sway.IUser> | undefined
    > => {
        const ref = this.ref();
        if (!ref) return undefined;

        return ref.get();
    };

    public where = (
        key: "uid" | "email" | "regionCode" | "city" | "region" | "country",
        operator: any,
        value: any,
    ): fire.TypedQuery<any> => {
        return this.collection().where(
            key,
            operator,
            value,
        ) as fire.TypedQuery<any>;
    };

    public getWithSettings = async (): Promise<
        sway.IUserWithSettingsAdmin | null | undefined
    > => {
        const snap = await this.snapshot();
        if (!snap) return null;

        const user = snap.data();
        if (!user) return null;

        const isAdmin = await this.isAdmin(user.uid);

        const settings = await this.getSettings();
        return {
            user,
            settings: settings || DEFAULT_USER_SETTINGS,
            isAdmin,
        };
    };

    public getWithoutSettings = async (): Promise<sway.IUser | undefined> => {
        const snap = await this.snapshot();
        if (!snap) return undefined;

        const user = snap.data();
        if (!user) return undefined;

        return user;
    };

    // Email uniqueness is verified by firebase in Auth rules
    private exists = async (): Promise<boolean> => {
        const snap = await this.snapshot();
        if (!snap) return false;

        return snap.exists;
    };

    public count = async (locale: sway.ILocale): Promise<number> => {
        // @ts-ignore
        const path: firebase.default.firestore.FieldPath = "locale.name";
        const snap = await this.collection()
            .where(path, "==", locale.name)
            .get();
        if (!snap) return 0;
        return snap.size;
    };

    public create = async (
        data: sway.IUser,
        isUpdating?: boolean,
    ): Promise<sway.IUser | undefined> => {
        const exists = await this.exists();
        if (exists) {
            if (!isUpdating) return undefined;
            const user = await this.update(data);
            return user;
        }

        const ref = this.ref();
        if (!ref) return undefined;

        const user: sway.IUser | void = await ref
            .set({
                ...data,
                createdAt:
                    this.firestoreConstructor.FieldValue.serverTimestamp(),
                updatedAt:
                    this.firestoreConstructor.FieldValue.serverTimestamp(),
            })
            .then(() => data)
            .catch(console.error);
        if (!user) return undefined;

        this.createUserSettings(user);

        return user;
    };

    public createUserSettings = async (
        user: sway.IUser,
    ): Promise<sway.IUserSettings | undefined> => {
        if (!user) return undefined;

        try {
            const fireSettings = new FireUserSettings(
                this.firestore,
                this.locale,
                this.firestoreConstructor,
                this.uid,
            );

            const snap = await fireSettings.snapshot();
            if (!snap) return undefined;
            if (snap.exists) {
                return snap.data();
            }

            return await fireSettings.create({
                ...DEFAULT_USER_SETTINGS,
                uid: user.uid,
            });
        } catch (error) {
            console.error(error);
        }
        return undefined;
    };

    public upsert = async (
        data: sway.IUser,
    ): Promise<sway.IUser | undefined> => {
        const exists = await this.exists();

        if (exists) {
            const user = await this.update(data);
            return user;
        }

        const ref = this.ref();
        if (!ref) return undefined;

        const user: sway.IUser | undefined = await ref
            .set(data)
            .then(() => data)
            .catch((error) => {
                console.error(error);
                return undefined;
            });
        return user;
    };

    public update = async (
        data: sway.IUser,
    ): Promise<sway.IUser | undefined> => {
        const ref = this.ref();
        if (!ref) return undefined;

        return ref
            .update({
                ...data,
                createdAt:
                    data.createdAt ||
                    this.firestoreConstructor.FieldValue.serverTimestamp(),
                updatedAt:
                    this.firestoreConstructor.FieldValue.serverTimestamp(),
            })
            .then(() => data)
            .catch((error) => {
                console.error(error);
                return undefined;
            });
    };

    public listen = (
        callback: (
            snapshot: fire.TypedDocumentSnapshot<sway.IUser>,
        ) => Promise<void>,
        errorCallback?: (params?: any) => undefined,
    ) => {
        const ref = this.ref();
        if (!ref) return undefined;

        return ref.onSnapshot({
            next: callback,
            error: errorCallback,
        });
    };

    private getSettings = async () => {
        const fireSettings = new FireUserSettings(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            this.uid,
        );
        return fireSettings.get();
    };

    private isAdmin = async (uid: string): Promise<boolean> => {
        const doc: fire.TypedDocumentReference<sway.IAdmin> = this.firestore
            .collection(Collections.Admins)
            .doc(uid);

        logDev("FireUsers.isAdmin - doc -", doc);
        if (!doc) return false;

        const snap: fire.TypedDocumentSnapshot<sway.IAdmin> = await doc.get();
        logDev("FireUsers.isAdmin - snap -", snap);
        return snap.exists;
    };
}

export default FireUsers;
