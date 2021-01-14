/// <reference types="cypress" />

declare namespace Cypress {
    interface Chainable<Subject = any> {
        persistence(): Chainable<Subject>;
        googleSignin(): Chainable<Subject>;
        signin(email: string, password: string): Chainable<Subject>;
        signinForm(email: string, password: string): Chainable<Subject>;
        signup(email: string, password: string): Chainable<Subject>;
    }
}