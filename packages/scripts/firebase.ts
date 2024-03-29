/** @format */

import * as admin from "firebase-admin";

const isTest = process.env.NODE_ENV === "test";

// eslint-disable-next-line
const emulate = isTest || process.env.REACT_APP_EMULATE == "1";
console.log("Scripting with Emulator?", emulate);
console.log("Scripting with GCLOUD_PROJECT", process.env.GCLOUD_PROJECT);
console.log("Scripting with FIREBASE_AUTH_EMULATOR_HOST", process.env.FIREBASE_AUTH_EMULATOR_HOST);
console.log("Scripting with FIRESTORE_EMULATOR_HOST", process.env.FIRESTORE_EMULATOR_HOST);
console.log("Scripting with REACT_APP_EMULATE", process.env.REACT_APP_EMULATE);

const firebaseConfig = {
    projectId: emulate ? process.env.GCLOUD_PROJECT : process.env.REACT_APP_PROJECT_ID,
    storageBucket: process.env.REACT_APP_STORAGE_BUCKET,
};

console.log(firebaseConfig);

admin.initializeApp(firebaseConfig);

const auth = admin.auth();
const bucket = admin.app().storage().bucket();
const firestoreConstructor = admin.firestore;
const db = firestoreConstructor();

if (emulate) {
    console.log("scripts - EMULATING. Setting db settings to emulator db");
    db.settings({
        host: "localhost:8080",
        ssl: false,
        experimentalForceLongPolling: true,
    });
} else {
    console.log("scripts - NOT EMULATING");
}

export { auth, firestoreConstructor, db, bucket };
