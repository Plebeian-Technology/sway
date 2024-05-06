#!/usr/bin/env zsh

export $(cat .env.development | xargs)

SID=${1}
curl -X GET "https://verify.twilio.com/v2/Services/$TWILIO_VERIFY_SERVICE_SID/Verifications/$SID" \
-u $TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN

# curl -X POST "https://verify.twilio.com/v2/Services/$TWILIO_VERIFY_SERVICE_SID/Verifications/${SID}" \
# --data-urlencode "Status=canceled" \
# -u $TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN

# PHONE=${1}
# curl -X POST "https://verify.twilio.com/v2/Services/$TWILIO_VERIFY_SERVICE_SID/Verifications/+1${PHONE}" \
# --data-urlencode "Status=approved" \
# -u $TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN

# curl -X POST "https://verify.twilio.com/v2/Services/VAXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX/Verifications/+15017122661" \
# --data-urlencode "Status=approved" \
# -u $TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN