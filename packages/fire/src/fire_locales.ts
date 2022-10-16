/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";
import AbstractFireSway from "./abstract_legis_firebase";
class FireLocales extends AbstractFireSway {
    private collection = (): fire.TypedCollectionReference<sway.ILocaleUsers> => {
        return this.firestore.collection(
            Collections.Locales,
        ) as fire.TypedCollectionReference<sway.ILocaleUsers>;
    };

    private ref = (
        locale: sway.ILocaleUsers | sway.ILocale,
    ): fire.TypedDocumentReference<sway.ILocaleUsers> => {
        return this.collection().doc(locale.name);
    };

    public snapshot = async (
        locale: sway.ILocaleUsers | sway.ILocale,
    ): Promise<fire.TypedDocumentSnapshot<sway.ILocaleUsers>> => {
        const ref = this.ref(locale);

        return ref.get();
    };

    public get = async (
        locale: sway.ILocaleUsers | sway.ILocale,
    ): Promise<sway.ILocaleUsers | undefined> => {
        return (await this.snapshot(locale))?.data();
    };

    public exists = async (locale: sway.ILocaleUsers | sway.ILocale): Promise<boolean> => {
        const snap = await this.snapshot(locale);
        if (!snap) return false;

        return snap.exists;
    };

    public create = async (
        locale: sway.ILocaleUsers,
    ): Promise<sway.ILocaleUsers | undefined | void> => {
        const exists = await this.exists(locale);
        if (exists) {
            return;
        }

        const ref = this.ref(locale);
        if (!ref) return;

        return ref
            .set(locale)
            .then(() => this.get(locale))
            .catch(this.logError);
    };

    public addUserToCount = async (
        locale: sway.ILocaleUsers,
        district: string,
        { addToAll }: { addToAll?: boolean },
    ): Promise<sway.ILocaleUsers | undefined | void> => {
        const data = await this.get(locale);
        if (!data) return;

        if (addToAll) {
            await this.ref(locale)
                .update({
                    // @ts-ignore
                    "userCount.all": this.firestoreConstructor.FieldValue.increment(1),
                })
                .catch(this.logError);
        }
        await this.ref(locale)
            .update({
                [`userCount.${district}`]: this.firestoreConstructor.FieldValue.increment(1),
            })
            .catch(this.logError);
        return this.get(locale);
    };
}

export default FireLocales;
