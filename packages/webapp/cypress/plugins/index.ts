/** @format */

/// <reference types="node" />
/// <reference types="cypress" />
// ***********************************************************
// This example plugins/index.js can be used to load plugins
//
// You can change the location of this file or turn off loading
// the plugins file with the 'pluginsFile' configuration option.
//
// You can read more here:
// https://on.cypress.io/plugins-guide
// ***********************************************************

// This function is called when a project is opened or re-opened (e.g. due to
// the project's config changing)

/**
 * @type {Cypress.PluginConfig}
 */
module.exports = (on: any, config: any) => {
    on(
        "before:browser:launch",
        (
            browser: Cypress.Browser,
            launchOptions: Cypress.BrowserLaunchOptions
        ) => {
            // `args` is an array of all the arguments that will
            // be passed to browsers when it launches
            console.log(launchOptions.args); // print all current args

            if (
                browser &&
                browser.family === "chromium" &&
                browser.name !== "electron"
            ) {
                // auto open devtools
                launchOptions.args.push("--auto-open-devtools-for-tabs");

                // whatever you return here becomes the launchOptions
                return launchOptions;
            }

            if (browser && browser.family === "firefox") {
                // auto open devtools
                launchOptions.args.push("-devtools");

                return launchOptions;
            }
        }
    );
};
