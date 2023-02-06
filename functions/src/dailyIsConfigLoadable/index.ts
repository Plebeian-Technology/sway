/** @format */

import * as functions from "firebase-functions";
import { get } from "lodash";
import { IFunctionsConfig } from "../utils";
const { logger } = functions;

// “At 00:00 in January.”
export const dailyIsConfigLoadable = functions.pubsub
    .schedule("0 0 * 1 *")
    .timeZone("America/New_York") // Users can choose timezone - default is America/Los_Angeles
    .onRun((_context: functions.EventContext) => {
        logger.info("Running config check at -", new Date());

        const config = functions.config() as IFunctionsConfig;

        const checks = [
            get(config, "sendgrid.welcometemplateid"), // 0
            get(config, "sendgrid.templateid"), // 1
            get(config, "sendgrid.invitetemplateid"), // 2
            get(config, "sendgrid.fromaddress"), // 3
            get(config, "sendgrid.legislatoremailtemplateid"), // 4
            get(config, "sendgrid.billoftheweektemplateid"), // 5
            get(config, "sendgrid.apikey"), // 6
            get(config, "twitter.consumer_key"), // 7
            get(config, "twitter.access_token_key"), // 8
            get(config, "twitter.access_token_secret"), // 9
            get(config, "twitter.consumer_secret"), // 10
            get(config, "twitter2.access_token_key"), // 11
            get(config, "twitter2.consumer_secret"), // 12
            get(config, "twitter2.consumer_key"), // 13
            get(config, "twitter2.access_token_secret"), // 14
            get(config, "geocode.apikey"), // 15
            get(config, "sway.isdevelopment"), // 16
            get(config, "sway.recaptcha.sitekey"), // 17
            get(config, "sway.recaptcha.secretkey"), // 18
            get(config, "twilio.account_sid"), // 19
            get(config, "twilio.auth_token"), // 20
            get(config, "twilio.from_number"), // 21
            get(config, "usps.id"), // 22
        ];
        const every = checks.every(Boolean);

        logger.info("Is every config value set / boolean true? ", every);
        if (!every) {
            checks.forEach((check: any, index: number) => {
                if (!check) {
                    logger.warn("Missing config value at index -", index);
                }
            });
        }

        return every;
    });
