import { Button, Grid, Typography, FormControlLabel, Switch, Box } from "@mui/material";
import { useForm } from "@inertiajs/react";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
}

const PhoneSmsNotifications = ({ user }: IProps) => {
    // Correctly initialize form data with user.sms_notifications_enabled
    const { data, setData, patch, processing } = useForm({
        user: {
            sms_notifications_enabled: user.sms_notifications_enabled,
        },
    });

    const phoneNumber = "2402582895";
    const contactName = "Sway Notifications";

    const vCardContent = `BEGIN:VCARD
VERSION:3.0
FN:${contactName}
TEL;TYPE=CELL:${phoneNumber}
END:VCARD`;

    const blob = new Blob([vCardContent], { type: "text/vcard" });
    const downloadUrl = URL.createObjectURL(blob);
    const filename = `${contactName.replace(/\s/g, "_")}.vcf`;

    const submit = (e: React.FormEvent) => {
        e.preventDefault();
        patch("/notifications/settings", {
            preserveScroll: true,
        });
    };

    return (
        <Grid container spacing={2}>
            <Grid size={12} sx={{ gap: 3, display: "flex", flexDirection: "column" }}>
                <Box component="form" onSubmit={submit} sx={{ display: "flex", alignItems: "center", gap: 2 }}>
                    <FormControlLabel
                        control={
                            <Switch
                                checked={data.user.sms_notifications_enabled}
                                onChange={(e) => setData("user", { ...data.user, sms_notifications_enabled: e.target.checked })}
                                color="secondary"
                            />
                        }
                        label="Enable SMS Notifications"
                    />
                    <Button
                        type="submit"
                        variant="contained"
                        color="secondary"
                        disabled={processing || data.user.sms_notifications_enabled === user.sms_notifications_enabled}
                    >
                        Save Preferences
                    </Button>
                </Box>

                <Typography>
                    Sway can keep you informed about new Bills of the Week by sending you a text message whenever a new
                    one is released. This will not happen often, you can expect at most one to three messages per week.
                </Typography>
                <Typography>
                    And if you ever opt-out by mistake, you can always opt back in by replying "START" to this phone
                    number. You can opt-out at any time by replying "STOP" to any message you receive from us.
                </Typography>
                <Typography>
                    Sway&apos;s phone number is{" "}
                    <Typography component={"span"} fontWeight={"bold"}>
                        {"(240) 258-2895"}
                    </Typography>
                    . You can save it to your contacts as &quot;Sway Notifications&quot; by clicking{" "}
                    <Button variant="contained" size="small" href={downloadUrl} download={filename}>
                        here
                    </Button>
                </Typography>
                <Typography>
                    IMPORTANT: This phone number cannot receive calls or messages, however, you may be billed by your
                    carrier if you do call or message this number. Message and data rates may apply. Please check with
                    your mobile carrier for details.
                </Typography>
            </Grid>
            <Grid size={12}></Grid>
        </Grid>
    );
};

export default PhoneSmsNotifications;
