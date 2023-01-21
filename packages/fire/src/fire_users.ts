/** @format */

import { Collections, DEFAULT_USER_SETTINGS } from "@sway/constants";
import { Timestamp } from "firebase/firestore";
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
        super(firestore, firestoreConstructor, locale);
        this.uid = uid;
    }

    private collection = (): fire.TypedCollectionReference<sway.IUser> => {
        return this.firestore.collection(
            Collections.Users,
        ) as fire.TypedCollectionReference<sway.IUser>;
    };

    public ref = (): fire.TypedDocumentReference<sway.IUser> | undefined => {
        if (!this.uid) {
            return;
        }
        return this.collection().doc(this.uid);
    };

    public snapshot = async (): Promise<fire.TypedDocumentSnapshot<sway.IUser> | undefined> => {
        const ref = this.ref();
        if (!ref) return undefined;

        return ref.get();
    };

    public where = (
        key: "uid" | "email" | "regionCode" | "city" | "region" | "country",
        operator: any,
        value: any,
    ): fire.TypedQuery<any> => {
        return this.collection().where(key, operator, value) as fire.TypedQuery<any>;
    };

    public getWithSettings = async (): Promise<sway.IUserWithSettingsAdmin | null | undefined> => {
        const snap = await this.snapshot().catch(this.logError);
        if (!snap) return null;

        const user = snap.data();
        if (!user) return null;

        const isAdmin = (await this.isAdmin(user.uid).catch(this.logError)) || false;

        const settings = await this.getSettings().catch(this.logError);
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
        const snap = await this.collection().where(path, "==", locale.name).get();
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
            return this.update(data);
        }

        const ref = this.ref();
        if (!ref) return undefined;

        const user: sway.IUser | void = await ref
            .set({
                ...data,
                createdAt: new Date(),
                updatedAt: new Date(),
            })
            .then(() => data)
            .catch(this.logError);
        if (!user) return undefined;

        this.createUserSettings(user).catch(this.logError);

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
            this.logError(error);
        }
        return undefined;
    };

    public upsert = async (data: sway.IUser): Promise<sway.IUser | undefined> => {
        const exists = await this.exists();

        if (exists) {
            return this.update(data);
        }

        const ref = this.ref();
        if (!ref) return undefined;

        const user: sway.IUser | undefined = await ref
            .set(data)
            .then(() => data)
            .catch((error) => {
                this.logError(error);
                return undefined;
            });
        return user;
    };

    public update = async (data: sway.IUser): Promise<sway.IUser | undefined> => {
        const ref = this.ref();
        if (!ref) return undefined;

        return ref
            .update({
                ...data,
                createdAt: data.createdAt
                    ? data.createdAt instanceof Timestamp
                        ? data?.createdAt?.toDate()
                        : data.createdAt
                    : new Date(),
                updatedAt: new Date(),
            })
            .then(() => data)
            .catch((error) => {
                this.logError(error);
                return undefined;
            });
    };

    public listen = (
        callback: (snapshot: fire.TypedDocumentSnapshot<sway.IUser>) => Promise<void>,
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

        if (!doc) return false;

        const snap: fire.TypedDocumentSnapshot<sway.IAdmin> = await doc.get();
        return snap.exists;
    };
}

export default FireUsers;
