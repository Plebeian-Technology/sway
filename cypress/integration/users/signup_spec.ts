/** @format */

describe("signup page", () => {
    it("has signup elements", () => {
        cy.visit("/signup");
        cy.persistence();

        cy.get("#subcontainer").then((container) => {
            expect(container.has("p"));
            cy.get("#subcontainer p").then((ps) => {
                expect(ps.length === 3);
                expect(ps[0].children.length === 1);
                expect(ps[0].children[0].textContent === " Sign Up Here");
                expect(ps[1].children.length === 1);
                expect(ps[1].children[0].textContent === "Forgot Password?");
                expect(ps[2].children.length === 0);
                expect(ps[2].textContent === "or");
            });
            cy.get("#subcontainer .buttons-container img").then((imgs) => {
                expect(imgs.length === 3);
                expect(imgs[0].textContent === "Sign in with Apple");
                expect(imgs[1].textContent === "Sign in with Google");
                expect(imgs[2].textContent === "Sign in with Twitter");
            });
        });

        cy.signin("legis@sway.vote", "password");
    });
});
