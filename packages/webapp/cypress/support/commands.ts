/** @format */

// https://docs.cypress.io/api/cypress-api/custom-commands.html

import {
    createUserWithEmailAndPassword,
    GoogleAuthProvider,
    signInWithCredential,
    signInWithEmailAndPassword,
} from "firebase/auth";
import { auth } from "../../src/firebase";

function persistence() {
    return cy.get("body").then((body) => {
        if (body.find("#alert-dialog-title").length) {
            cy.get("#alert-dialog-title").then((el) => {
                if (!el) return el;

                if (el.text() === "Private Computer?") {
                    return cy.get("button").then((buttons) => {
                        expect(buttons.length === 2);
                        expect(buttons[0].textContent === "NO");
                        expect(buttons[1].textContent === "YES");
                        buttons[1].click();
                    });
                }
                return el;
            });
        }
        return cy.wrap(body);
    });
}

// https://firebase.google.com/docs/emulator-suite/connect_auth#non-interactive_testing_3
async function googleSignin(email?: string) {
    const user = {
        sub: "abc123",
        email: email || "foo@example.com",
        email_verified: true,
    };
    console.log("signing into google");

    signInWithCredential(auth, GoogleAuthProvider.credential(JSON.stringify(user))).catch(
        console.error,
    );
}

function signup(email: string, password: string) {
    fetch("http://localhost:9099/emulator/v1/projects/sway-dev/accounts", {
        method: "DELETE",
    })
        .then((deleted) => {
            console.log("DELETED", deleted);

            createUserWithEmailAndPassword(auth, email, password).catch(console.error);
            return fetch("http://localhost:9099/emulator/v1/projects/sway-dev/oobCodes")
                .then((response) => response.json())
                .then(console.log)
                .catch(console.error);
        })
        .catch(console.error);
}

function signin(email: string, password: string) {
    return signInWithEmailAndPassword(auth, email, password);
}

function signinForm(email: string, password: string) {
    cy.visit("/signin");
    cy.persistence();
    cy.get("form.login-form").should("exist");
    cy.get("#userEmail").should("exist").type(email);
    cy.get("#userPassword").should("exist").type(password);
    cy.get("button[type='submit']").click();
}

Cypress.Commands.add("persistence", persistence);
// @ts-ignore
Cypress.Commands.add("googleSignin", googleSignin);
Cypress.Commands.add("signup", signup);
// @ts-ignore
Cypress.Commands.add("signin", signin);
Cypress.Commands.add("signinForm", signinForm);
