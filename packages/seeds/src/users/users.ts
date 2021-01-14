import { Collections } from "@sway/constants";
import * as faker from "faker";
import { sway } from "sway";
import { db, firestore } from "../firebase";

export const seedUsers = (uid: string, locale: sway.ILocale): sway.IUser | undefined => {
    console.log("seeding user");
    if (!uid) return;

    if (process.env.NODE_ENV === "production") {
        console.log("production: skipping user seeding");
        return;
    };

    const collection = db.collection(Collections.Users);
    if (!collection) return;

    const ref = collection.doc(uid);
    if (!ref) return;

    const user: Partial<sway.IUser> = {
        createdAt: firestore.FieldValue.serverTimestamp(),
        updatedAt: firestore.FieldValue.serverTimestamp(),
        email: faker.internet.email(),
        uid: uid,
        isRegistrationComplete: true,
        locale: {
            name: locale.name,
            district: 0,
            isSwayConfirmed: false,
            isRegisteredToVote: false,
        } as sway.IUserLocale,
        name: faker.name.findName(),
        title: faker.name.title(),
        address1: faker.address.streetAddress(),
        address2: faker.address.secondaryAddress(),
        city: faker.address.city(),
        region: faker.address.state(),
        country: "United States",
        postalCode: faker.address.zipCode(),
        postalCodeExtension: "",
        phone: faker.phone.phoneNumber(),
    }

    ref.set(user).then(() => console.log(`created new user ${uid}`)).catch(console.error);

    return user as sway.IUser;
}