import * as fs from "fs";
import { Auth, google } from "googleapis";
import * as readline from "readline";
import { sway } from "sway";
import {
    SCOPES,
    TOKEN_PATH
} from "./constants";


/**
 * Create an OAuth2 client with the given credentials, and then execute the
 * given callback function.
 * @param {Object} credentials The authorization client credentials.
 * @param {function} callback The callback to call with the authorized client.
 */
export function authorize(
    credentials: {
        installed: {
            client_secret: string;
            client_id: string;
            redirect_uris: string[];
        };
    },
    locale: sway.ILocale,
    callback: (auth: Auth.OAuth2Client, locale: sway.ILocale) => void,
) {
    const { client_secret, client_id, redirect_uris } = credentials.installed;
    const oAuth2Client: Auth.OAuth2Client = new google.auth.OAuth2(
        client_id,
        client_secret,
        redirect_uris[0],
    );

    // Check if we have previously stored a token.
    fs.readFile(TOKEN_PATH, "utf8", (err: Error | null, token: string) => {
        if (err) return getNewToken(oAuth2Client, locale, callback);
        oAuth2Client.setCredentials(JSON.parse(token));
        callback(oAuth2Client, locale);
    });
}

/**
 * Get and store new token after prompting for user authorization, and then
 * execute the given callback with the authorized OAuth2 client.
 * @param {google.auth.OAuth2} oAuth2Client The OAuth2 client to get token for.
 * @param {getEventsCallback} callback The callback for the authorized client.
 */
export function getNewToken(
    oAuth2Client: Auth.OAuth2Client,
    locale: sway.ILocale,
    callback: (client: Auth.OAuth2Client, locale: sway.ILocale) => void,
) {
    const authUrl = oAuth2Client.generateAuthUrl({
        access_type: "offline",
        scope: SCOPES,
    });
    console.log("Authorize this app by visiting this url:", authUrl);
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
    });
    rl.question("Enter the code from that page here: ", (code) => {
        rl.close();
        oAuth2Client.getToken(
            code,
            (err: Error | null, token: Auth.Credentials | null | undefined) => {
                if (err || !token)
                    return console.error(
                        "Error while trying to retrieve access token",
                        err,
                    );
                oAuth2Client.setCredentials(token);
                // Store the token to disk for later program executions
                fs.writeFile(TOKEN_PATH, JSON.stringify(token), (err) => {
                    if (err) return console.error(err);
                    console.log("Token stored to", TOKEN_PATH);
                });
                callback(oAuth2Client, locale);
            },
        );
    });
}