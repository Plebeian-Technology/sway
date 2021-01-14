/** @format */

import * as admin from "firebase-admin";

const IS_DEVELOPMENT = process.env.NODE_ENV === "development";
const isTest = process.env.NODE_ENV === "test";

const emulate = isTest || !!process.env.REACT_APP_EMULATE;
console.log("Seeding with Emulator?", emulate);
console.log("Seeding with GCLOUD_PROJECT", process.env.GCLOUD_PROJECT);
console.log("Seeding with FIREBASE_AUTH_EMULATOR_HOST", process.env.FIREBASE_AUTH_EMULATOR_HOST);
console.log("Seeding with FIRESTORE_EMULATOR_HOST", process.env.FIRESTORE_EMULATOR_HOST);
console.log("Seeding with REACT_APP_EMULATE", process.env.REACT_APP_EMULATE);

const firebaseConfig = {
    projectId: emulate
        ? process.env.GCLOUD_PROJECT
        : IS_DEVELOPMENT
        ? process.env.REACT_APP_DEV_PROJECT_ID
        : process.env.REACT_APP_PROJECT_ID
};

console.log(firebaseConfig);


admin.initializeApp(firebaseConfig);

const auth = admin.auth();
const firestore = admin.firestore;
const db = firestore();

if (emulate) {
    console.log("EMULTING. Setting db settings to emulator db");
    db.settings({
        host: process.env.FIRESTORE_EMULATOR_HOST,
        ssl: false,
    });
} else {
    console.log("NOT EMULATING");

}

export {
    auth, firestore, db
}
