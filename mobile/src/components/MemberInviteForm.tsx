// @lat: [[mobile-org-membership-components-design#MemberInviteForm]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { FormField } from "./ui/FormField";
import { Pressable } from "./ui/Pressable";
import { useMemberInvite } from "../hooks/useMemberInvite";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

export interface MemberInviteFormProps {
    orgId: number;
    onInvited?: () => void;
    testID?: string;
}

export function MemberInviteForm({ orgId, onInvited, testID }: MemberInviteFormProps) {
    const [email, setEmail] = useState("");
    const { invite, busy, error } = useMemberInvite();

    const handleSubmit = async () => {
        if (!email.trim()) return;
        try {
            await invite(orgId, email.trim());
            setEmail("");
            onInvited?.();
        } catch {
            // @lat: [[mobile-org-membership-components-design#Empty catch blocks: error already held by the hook]]
        }
    };

    return (
        <View testID={testID ?? "member-invite-form"} className="mb-4">
            <Text className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-3">
                {PARITY_COPY.members.inviteLabel}
            </Text>
            <FormField
                label="Email"
                value={email}
                onChangeText={setEmail}
                placeholder="member@example.com"
                keyboardType="email-address"
                autoComplete="email"
                textContentType="emailAddress"
                error={error?.message}
                disabled={busy}
                testID="member-invite-email"
            />
            <Pressable
                variant="default"
                onPress={() => {
                    void handleSubmit();
                }}
                disabled={busy || !email.trim()}
                accessibilityLabel={PARITY_COPY.members.inviteSubmitLabel}
            >
                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                    {busy ? "Sending…" : PARITY_COPY.members.inviteSubmitLabel}
                </Text>
            </Pressable>
        </View>
    );
}

export default MemberInviteForm;
