/** @format */

import { Collections } from "@sway/constants";
import { fire, sway } from "sway";

class FireLocales {
    firestore: any;

    constructor(firestore: any) {
        this.firestore = firestore;
    }

    private name = (city: string, region: string, country: string) =>
        `${city}-${region}-${country}`;

    private collection = (): fire.TypedCollectionReference<sway.ILocale> => {
        return this.firestore.collection(
            Collections.Locales,
        ) as fire.TypedCollectionReference<sway.ILocale>;
    };

    private ref = (
        name: string,
    ): fire.TypedDocumentReference<sway.ILocale> => {
        return this.collection().doc(name);
    };

    private snapshot = (
        name: string,
    ): Promise<fire.TypedDocumentSnapshot<sway.ILocale>> => {
        return this.ref(name).get();
    };

    public get = async (name: string): Promise<sway.ILocale | void> => {
        const snap = await this.snapshot(name);
        if (!snap) return;

        return snap.data();
    };

    public list = async (): Promise<sway.ILocale[]> => {
        const snap: fire.TypedQuerySnapshot<sway.ILocale> = await this.collection().get();
        return snap.docs.map((doc) => doc.data());
    };

    public create = async (
        _city: string,
        _region: string,
        _country: string,
        postalCodes: string[],
        districts: number[],
    ): Promise<sway.ILocale | void> => {
        const _name = this.name(_city, _region, _country);
        return this.ref(_name)
            .set({
                _city,
                _region,
                _country,
                name: _name,
                postalCodes,
                districts,
            })
            .then(async () => await this.get(_name));
    };
}

export default FireLocales;
