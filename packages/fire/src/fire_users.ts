/** @format */

import { Collections, DEFAULT_USER_SETTINGS } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
import FireUserSettings from "./fire_user_settings";
class FireUsers extends AbstractFireSway {
    uid: string;

    constructor(
        firestore: any,
        locale: sway.ILocale | null | undefined,
        firestoreConstructor: any,
        uid: string
    ) {
        super(firestore, locale, firestoreConstructor);
        this.uid = uid;
    }

    private collection = (): fire.TypedCollectionReference<sway.IUser> => {
        return this.firestore.collection(
            Collections.Users
        ) as fire.TypedCollectionReference<sway.IUser>;
    };

    private ref = (): fire.TypedDocumentReference<sway.IUser> | undefined => {
        return this.collection().doc(this.uid);
    };

    private snapshot = async (): Promise<fire.TypedDocumentSnapshot<sway.IUser> | undefined> => {
        const ref = this.ref();
        if (!ref) return;

        return ref.get();
    };

    public list = async (): Promise<sway.IUser[] | undefined> => {
        const snap: fire.TypedQuerySnapshot<sway.IUser> = await this.collection().get();
        if (!snap) return;

        const docs: fire.TypedQueryDocumentSnapshot<sway.IUser>[] =
            snap.docs;

        return Promise.all(
            docs.map(
                async (doc: fire.TypedQueryDocumentSnapshot<sway.IUser>) => {
                    return doc.data();
                }
            )
        );
    };

    public where = (
        key:
            | "uid"
            | "email",
        operator: any,
        value: any
    ): fire.TypedQuery<any> => {
        return this.collection().where(key, operator, value) as fire.TypedQuery<any>;
    };

    public get = async (): Promise<sway.IUserWithSettingsAdmin | null | undefined> => {
        const snap = await this.snapshot();
        if (!snap) return null;

        const user = snap.data();
        if (!user) return null;

        const settings = await this.getSettings();

        const isAdmin = await this.isAdmin(user.uid);
        return {
            user,
            settings: settings || DEFAULT_USER_SETTINGS,
            isAdmin,
        };
    };

    public getWithoutAdminSettings = async(): Promise<sway.IUser | undefined> => {
        const snap = await this.snapshot();
        if (!snap) return;

        const user = snap.data();
        if (!user) return;

        return user;
    }

    private exists = async (
        user: sway.IUser
    ): Promise<[boolean, string]> => {
        const exists = await this.get();
        if (exists) {
            return [true, "user exists"];
        }
        if (!user) return [false, ""];

        const existsEmail = await this.collection()
            .where("email", "==", user.email)
            .get();
        if (existsEmail.size > 0) {
            return [true, "user exists"];
        }
        const existsPhone = await this.collection()
            .where("phone", "==", user.phone)
            .get();
        if (existsPhone.size > 0) {
            return [true, "user exists"];
        }

        return [false, ""];
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
        data: sway.IUser, isUpdating?: boolean,
    ): Promise<sway.IUser | undefined> => {
        const [exists] = await this.exists(data);
        if (exists) {
            if (!isUpdating) return;
            const user = await this.update(data);
            return user;
        };

        const ref = this.ref();
        if (!ref) return;

        const user: sway.IUser | void = await ref
            .set(data)
            .then(() => data)
            .catch(console.error);
        if (!user) return;

        try {
            const fireSettings = new FireUserSettings(
                this.firestore,
                this.locale,
                this.firestoreConstructor,
                this.uid
            );
            await fireSettings.create({
                ...DEFAULT_USER_SETTINGS,
                uid: user.uid,
            });
        } catch (error) {
            console.error(error);
        }

        return user;
    };

    public upsert = async (
        data: sway.IUser
    ): Promise<sway.IUser | undefined> => {
        const [exists] = await this.exists(data);

        if (exists) {
            const user = await this.update(data);
            return user;
        }

        const ref = this.ref();
        if (!ref) return;

        const user: sway.IUser | undefined = await ref.set(data).then(() => data);
        return user;
    };

    public update = async (
        data: sway.IUser
    ): Promise<sway.IUser | undefined> => {
        const ref = this.ref();
        if (!ref) return;

        return ref.update(data).then(() => data);
    };

    public listen = (
        callback: (
            snapshot: fire.TypedDocumentSnapshot<sway.IUser>
        ) => Promise<void>,
        errorCallback?: (params?: any) => undefined
    ) => {
        const ref = this.ref();
        if (!ref) return;

        return ref.onSnapshot({
            next: callback,
            error: errorCallback,
        });
    };

    private isAdmin = async (uid: string): Promise<boolean> => {
        const doc: fire.TypedDocumentReference<sway.IAdmin> = this.firestore
            .collection(Collections.Admins)
            .doc(uid);
        if (!doc) return false;

        const snap: fire.TypedDocumentSnapshot<sway.IAdmin> = await doc.get();
        return snap.exists;
    };

    private getSettings = async () => {
        const fireSettings = new FireUserSettings(
            this.firestore,
            this.locale,
            this.firestoreConstructor,
            this.uid
        );
        return fireSettings.get();
    };
}

export default FireUsers;
