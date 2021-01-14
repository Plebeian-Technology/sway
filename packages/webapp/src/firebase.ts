/** @format */

import { SWAY_CACHING_OKAY_COOKIE } from "@sway/constants";
import firebase from "firebase/app";
import "firebase/auth";
import "firebase/firestore";
import "firebase/functions";
import "firebase/messaging";

const IS_DEVELOPMENT = process.env.NODE_ENV === "development";

console.log("process.env.REACT_APP_EMULATE", process.env.REACT_APP_EMULATE);
console.log("process.env.NODE_ENV", process.env.NODE_ENV);

const emulate =
    process.env.NODE_ENV === "test" ||
    !!process.env.REACT_APP_EMULATE
const cachingCookie: string | null = localStorage.getItem(
    SWAY_CACHING_OKAY_COOKIE
);

IS_DEVELOPMENT && console.log("EMULATING?", emulate);

const firebaseConfig = {
    apiKey: emulate
        ? "an_api_key"
        : IS_DEVELOPMENT
        ? process.env.REACT_APP_DEV_API_KEY
        : process.env.REACT_APP_API_KEY,
    authDomain: emulate
        ? "an_auth_domain"
        : IS_DEVELOPMENT
        ? process.env.REACT_APP_DEV_AUTH_DOMAIN
        : process.env.REACT_APP_AUTH_DOMAIN,
    databaseURL: emulate
        ? "a_database_url"
        : IS_DEVELOPMENT
        ? process.env.REACT_APP_DEV_DATABASE_URL
        : process.env.REACT_APP_DATABASE_URL,
    projectId: emulate
        ? "sway-dev-3187f"
        : IS_DEVELOPMENT
        ? process.env.REACT_APP_DEV_PROJECT_ID
        : process.env.REACT_APP_PROJECT_ID,
    storageBucket: emulate
        ? "a_storage_bucket"
        : IS_DEVELOPMENT
        ? process.env.REACT_APP_DEV_STORAGE_BUCKET
        : process.env.REACT_APP_STORAGE_BUCKET,
    messagingSenderId: emulate
        ? "a_message_sender_id"
        : IS_DEVELOPMENT
        ? process.env.REACT_APP_DEV_MESSAGING_SENDER_ID
        : process.env.REACT_APP_MESSAGING_SENDER_ID,
    appId: emulate
        ? "an_app_id"
        : IS_DEVELOPMENT
        ? process.env.REACT_APP_DEV_APP_ID
        : process.env.REACT_APP_APP_ID,
};

firebase.initializeApp(firebaseConfig);

const FieldValue = firebase.firestore.FieldValue;
const firestoreConstructor = firebase.firestore;
const authConstructor = firebase.auth;
const auth = authConstructor();
const functions = firebase.functions();
const firestore = firestoreConstructor();

let messaging: firebase.messaging.Messaging | null = null;
if (firebase.messaging.isSupported()) {
    messaging = firebase.messaging();
}

if (emulate) {
    auth.useEmulator("http://localhost:9099");
    functions.useEmulator("localhost", 5001);
    firestore.settings({
        host: "localhost:8080",
        ssl: false,
        experimentalForceLongPolling: true,
    });
} else if (cachingCookie === "1") {
    firestore
        .enablePersistence({ synchronizeTabs: true })
        .then(() => {
            if (IS_DEVELOPMENT) console.log("persistence enabled");
        })
        .catch((err) => {
            if (IS_DEVELOPMENT) {
                console.log("error enabling firestore persistence");
                console.error(err);
            }
            if (err.code === "failed-precondition") {
                if (IS_DEVELOPMENT) {
                    console.log("cannot enable persistence in multiple tabs");
                }
            } else if (err.code === "unimplemented") {
                if (IS_DEVELOPMENT) {
                    console.log("browser does not support persistence");
                }
            }
        });
}

export {
    FieldValue,
    auth,
    authConstructor,
    functions,
    firestoreConstructor,
    firestore,
    messaging,
};
