import * as admin from "firebase-admin";
import "firebase-functions";

admin.initializeApp();

export const storage = admin.storage();
export const bucket = storage.bucket();
export const firestore = admin.firestore;
export const db = firestore();
export const messaging = admin.messaging();
