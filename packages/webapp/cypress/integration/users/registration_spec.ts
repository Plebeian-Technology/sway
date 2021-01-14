/** @format */

describe("registration page", () => {
    it("loads the registration page after signing in", async () => {
        cy.persistence().then(() => {
            cy.signup(`foo-${new Date().toString()}@example.com`, "tacoC@t1!").then((data) => {
                cy.persistence().then(() => {
                    cy.signinForm("foo@example.com", "tacoC@t1!").then(() => {
                        cy.get("button")
                            .should("exist")
                            .then((button) => {
                                expect(button.text()).equal(
                                    "COMPLETE SWAY REGISTRATION"
                                );
                            });
                    });
                });
            });
        });
    });
});
