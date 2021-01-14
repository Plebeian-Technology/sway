import * as admin from "firebase-admin"
import "firebase-functions"

admin.initializeApp();

export const firestore = admin.firestore;
export const db = firestore();
export const messaging = admin.messaging();
