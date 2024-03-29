/** @format */

import * as admin from "firebase-admin";

const isTest = process.env.NODE_ENV === "test";

// eslint-disable-next-line
const emulate = isTest || process.env.REACT_APP_EMULATE == "1";
console.log("Seeding with Emulator?", emulate);
console.log("Seeding with GCLOUD_PROJECT", process.env.GCLOUD_PROJECT);
console.log("Seeding with FIREBASE_AUTH_EMULATOR_HOST", process.env.FIREBASE_AUTH_EMULATOR_HOST);
console.log("Seeding with FIRESTORE_EMULATOR_HOST", process.env.FIRESTORE_EMULATOR_HOST);
console.log("Seeding with REACT_APP_EMULATE", process.env.REACT_APP_EMULATE);

const firebaseConfig = {
    projectId: emulate ? process.env.GCLOUD_PROJECT : process.env.REACT_APP_PROJECT_ID,
    storageBucket: emulate ? "a_storage_bucket" : process.env.REACT_APP_STORAGE_BUCKET,
};

console.log(firebaseConfig);

admin.initializeApp(firebaseConfig);

const auth = admin.auth();
const firestoreConstructor = admin.firestore;
const db = firestoreConstructor();
const storage = admin.storage();
const bucket = storage.bucket();

if (emulate) {
    console.log("seeds - EMULATING. Setting db settings to emulator db");
    db.settings({
        host: "localhost:8080",
        ssl: false,
        experimentalForceLongPolling: true,
    });
    // functions.useEmulator("localhost", 5001);
    // firebase.storage().useEmulator("localhost", 9199);
} else {
    console.log("seeds - NOT EMULATING");
}

export { auth, firestoreConstructor, db, storage, bucket };
