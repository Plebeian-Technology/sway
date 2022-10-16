export const isEmptyObject = (obj: any) => {
    if (!obj) return true;

    for (const key in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, key)) return false;
    }
    return true;
};

export interface IFunctionsConfig {
    sendgrid: {
        welcometemplateid: string;
        templateid: string;
        invitetemplateid: string;
        fromaddress: string;
        legislatoremailtemplateid: string;
        billoftheweektemplateid: string;
        apikey: string;
    };
    twitter: {
        consumer_key: string;
        access_token_key: string;
        access_token_secret: string;
        consumer_secret: string;
    };
    twitter2: {
        access_token_key: string;
        consumer_secret: string;
        consumer_key: string;
        access_token_secret: string;
    };
    geocode: {
        apikey: string;
    };
    sway: {
        isdevelopment: "true" | "false";
        recaptcha: {
            sitekey: string;
            secretkey: string;
        };
    };
    twilio: {
        account_sid: string;
        auth_token: string;
        from_number: string;
    };
    usps: {
        id: string;
    };
}
