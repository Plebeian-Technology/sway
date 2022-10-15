/** @format */

// V9
// import firebase from "firebase/app"
import { SwayStorage } from "@sway/constants";
import { connectAuthEmulator, getAuth } from "firebase/auth";
// V8
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";
import { connectFunctionsEmulator, getFunctions } from "firebase/functions";
import { localGet } from "./utils";

// import "firebase/compat/auth";
// import "firebase/compat/functions";
// import { enableIndexedDbPersistence, getFirestore, serverTimestamp, increment, arrayUnion, arrayRemove } from "firebase/firestore";

const IS_DEVELOPMENT = process.env.NODE_ENV === "development";
const IS_EMULATE = process.env.NODE_ENV === "test" || !!process.env.REACT_APP_EMULATE;
const cachingCookie = localGet(SwayStorage.Local.User.FirebaseCaching);

IS_DEVELOPMENT && console.log("(dev) EMULATING?", IS_EMULATE);
IS_DEVELOPMENT && console.log("(dev) REACT_APP_API_KEY", process.env.REACT_APP_API_KEY);
IS_DEVELOPMENT && console.log("(dev) REACT_APP_AUTH_DOMAIN", process.env.REACT_APP_AUTH_DOMAIN);
IS_DEVELOPMENT && console.log("(dev) REACT_APP_DATABASE_URL", process.env.REACT_APP_DATABASE_URL);
IS_DEVELOPMENT && console.log("(dev) REACT_APP_PROJECT_ID", process.env.REACT_APP_PROJECT_ID);
IS_DEVELOPMENT &&
    console.log("(dev) REACT_APP_STORAGE_BUCKET", process.env.REACT_APP_STORAGE_BUCKET);
IS_DEVELOPMENT &&
    console.log("(dev) REACT_APP_MESSAGING_SENDER_ID", process.env.REACT_APP_MESSAGING_SENDER_ID);
IS_DEVELOPMENT && console.log("(dev) REACT_APP_APP_ID", process.env.REACT_APP_APP_ID);

const firebaseConfig = {
    apiKey: IS_EMULATE ? "an_api_key" : process.env.REACT_APP_API_KEY,
    authDomain: IS_EMULATE ? "an_auth_domain" : process.env.REACT_APP_AUTH_DOMAIN,
    databaseURL: IS_EMULATE ? "a_database_url" : process.env.REACT_APP_DATABASE_URL,
    projectId: IS_EMULATE ? "sway-dev-3187f" : process.env.REACT_APP_PROJECT_ID,
    storageBucket: IS_EMULATE ? "a_storage_bucket" : process.env.REACT_APP_STORAGE_BUCKET,
    messagingSenderId: IS_EMULATE
        ? "a_message_sender_id"
        : process.env.REACT_APP_MESSAGING_SENDER_ID,
    appId: IS_EMULATE ? "an_app_id" : process.env.REACT_APP_APP_ID,
};

const firebaseApp = firebase.initializeApp(firebaseConfig);

// V9
const auth = getAuth(firebaseApp);
const functions = getFunctions(firebaseApp);
// const firestore = getFirestore(firebaseApp);
// firestore.app.automaticDataCollectionEnabled = false;

// V8
const FieldValue = firebase.firestore.FieldValue;
const firestore = firebase.firestore();
// const authConstructor = firebase.auth;
// const auth = authConstructor(); // V8
// const functions = firebase.functions();

// let messaging: firebase.messaging.Messaging | null = null;
// if (firebase.messaging.isSupported()) {
//     messaging = firebase.messaging();
// }

if (IS_EMULATE) {
    // V9
    connectAuthEmulator(auth, "http://localhost:9099");
    connectFunctionsEmulator(functions, "localhost", 5001);
    // connectFirestoreEmulator(firestore, "localhost", 8080)

    // V8
    // auth.useEmulator("http://localhost:9099"); // V8
    // functions.useEmulator("localhost", 5001);
    firestore.settings({
        host: "localhost:8080",
        ssl: false,
        experimentalForceLongPolling: true,
    });
    // firebase.storage().useEmulator("localhost", 9199);
} else if (cachingCookie === "1") {
    // V9
    // enableIndexedDbPersistence(firestore)

    // V8
    firestore
        .enablePersistence({ synchronizeTabs: true })
        .then(() => {
            if (IS_DEVELOPMENT) console.log("(dev) persistence enabled");
        })
        .catch((err) => {
            if (IS_DEVELOPMENT) {
                console.log("(dev) error enabling firestore persistence");
            }
            console.error(err);
            if (err.code === "failed-precondition") {
                if (IS_DEVELOPMENT) {
                    console.log("(dev) cannot enable persistence in multiple tabs");
                }
            } else if (err.code === "unimplemented") {
                if (IS_DEVELOPMENT) {
                    console.log("(dev) browser does not support persistence");
                }
            }
        });
}

export { auth, firestore, functions, FieldValue };
