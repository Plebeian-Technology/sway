import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import "firebase-functions";
import { arrayUnion, increment, serverTimestamp } from "firebase/firestore";

admin.initializeApp();

export const storage = admin.storage();
export const bucket = storage.bucket();
export const firestoreConstructor = {
    FieldValue: {
        increment: admin.firestore?.FieldValue?.increment || FieldValue?.increment || increment,
        arrayUnion: admin.firestore?.FieldValue?.arrayUnion || FieldValue?.arrayUnion || arrayUnion,
        serverTimestamp:
            admin.firestore?.FieldValue?.serverTimestamp ||
            FieldValue?.serverTimestamp ||
            serverTimestamp,
    },
    Timestamp: admin.firestore?.Timestamp || Timestamp,
};
export const db = admin.firestore();
export const messaging = admin.messaging();
