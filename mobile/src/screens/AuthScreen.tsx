// @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile authentication screen]]
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import { KeyRound, Landmark, Megaphone, Vote } from "lucide-react-native";
import React, { useRef, useState } from "react";
import {
    ActivityIndicator,
    Image,
    KeyboardAvoidingView,
    Linking,
    Platform,
    ScrollView,
    Text,
    View,
} from "react-native";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { ApiRequestError } from "../api/errors";
import { NoPasskeyError, passkeyAuth, PasskeyUnsupportedError } from "../auth/passkeyAuth";
import { smsAuth } from "../auth/smsAuth";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/Card";
import { FormField } from "../components/ui/FormField";
import { Pressable } from "../components/ui/Pressable";
import type { AuthStackParamList } from "../navigation/types";
import { shadowBold } from "../theme/effects";
import { useTheme } from "../theme/ThemeProvider";
import { swayTokens } from "../theme/tokens";
import { PHONE_INPUT_TRANSFORMER, removeNonDigits } from "../utils/phone";

// @lat: [[mobile-auth-and-onboarding-flow#AuthStack#types.ts's AuthStackParamList]]
type Nav = NativeStackNavigationProp<AuthStackParamList, "Auth">;

export default function AuthScreen() {
    const nav = useNavigation<Nav>();
    const { colorScheme } = useTheme();
    const t = swayTokens[colorScheme];

    // @lat: [[mobile-auth-and-onboarding-flow#AuthScreen]]
    const [phone, setPhone] = useState("");
    const [code, setCode] = useState("");
    const [isConfirmingPhone, setConfirmingPhone] = useState(false);
    const [isLoading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    // @lat: [[mobile-auth-and-onboarding-flow#AuthScreen#Held SMS-verified token]]
    const heldSmsVerifiedToken = useRef<string | null>(null);

    const submitLabel = isConfirmingPhone
        ? PARITY_COPY.auth.passkeyPanel.confirmCode
        : PARITY_COPY.auth.passkeyPanel.continuePhone;

    const handleSubmit = async () => {
        if (removeNonDigits(phone).length !== 10) {
            setError(PARITY_COPY.auth.passkeyPanel.validationPhone);
            return;
        }
        setError(null);

        if (isConfirmingPhone) {
            if (!code.trim()) return;
            setLoading(true);
            try {
                if (!heldSmsVerifiedToken.current) {
                    const { sms_verified_token } = await smsAuth.verifyCode(phone, code);
                    heldSmsVerifiedToken.current = sms_verified_token;
                }
                await passkeyAuth.register(phone, heldSmsVerifiedToken.current);
                heldSmsVerifiedToken.current = null;
            } catch (e) {
                if (e instanceof ApiRequestError && e.code === "invalid_sms_token") heldSmsVerifiedToken.current = null;
                // @lat: [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile passkey error translation]]
                if (e instanceof NoPasskeyError) return;
                setError(e instanceof Error ? e.message : PARITY_COPY.auth.passkeyPanel.verifyError);
            } finally {
                setLoading(false);
            }
            return;
        }

        setLoading(true);
        try {
            await passkeyAuth.signIn(phone);
        } catch (e) {
            if (e instanceof PasskeyUnsupportedError) {
                nav.navigate("DeviceUnsupported");
                return;
            }
            if (e instanceof NoPasskeyError) {
                try {
                    await smsAuth.requestCode(phone);
                    setConfirmingPhone(true);
                } catch (_smsErr) {
                    setError(PARITY_COPY.auth.passkeyPanel.requestCodeError);
                }
                return;
            }
            setError(PARITY_COPY.auth.passkeyPanel.signInError);
        } finally {
            setLoading(false);
        }
    };

    const handleDiscoverableSignIn = async () => {
        setLoading(true);
        setError(null);
        try {
            await passkeyAuth.signInDiscoverable();
        } catch (e) {
            if (e instanceof PasskeyUnsupportedError) {
                nav.navigate("DeviceUnsupported");
                return;
            }
            if (e instanceof NoPasskeyError) return;
            setError(PARITY_COPY.auth.passkeyPanel.signInError);
        } finally {
            setLoading(false);
        }
    };

    const handleCancel = () => {
        heldSmsVerifiedToken.current = null;
        setCode("");
        setConfirmingPhone(false);
        setError(null);
    };

    // @lat: [[mobile-auth-and-onboarding-flow#AuthScreen#Why "Preview Sway" opens a browser instead of navigating]]
    const handlePreviewSway = () => void Linking.openURL(PARITY_COPY.auth.passkeyPanel.previewSwayUrl);

    return (
        <KeyboardAvoidingView
            behavior={Platform.OS === "ios" ? "padding" : undefined}
            className="flex-1 bg-dominant-light dark:bg-dominant-dark"
        >
            <ScrollView
                className="flex-1"
                contentContainerClassName="p-6"
                contentInsetAdjustmentBehavior="automatic"
                testID="auth-screen"
                keyboardShouldPersistTaps="handled"
            >
                <View className="flex-row items-center gap-3 mb-5" testID="auth-brand">
                    <Image
                        source={require("../../assets/sway-logo.png")}
                        accessibilityLabel="Sway"
                        className="w-11 h-11 rounded-xl"
                        resizeMode="cover"
                    />
                    <View className="flex-1">
                        <Text className="text-xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            Sway
                        </Text>
                    </View>
                </View>

                <View className="gap-2.5 mb-5" testID="auth-hero">
                    <Text
                        accessibilityRole="header"
                        className="text-3xl font-open-sans-semibold leading-tight text-foreground-light dark:text-foreground-dark"
                    >
                        {PARITY_COPY.auth.hero.headline}
                    </Text>
                    <Text className="text-base font-open-sans-light leading-6 text-muted-foreground-light dark:text-muted-foreground-dark">
                        {PARITY_COPY.auth.hero.paragraph}
                    </Text>
                </View>

                <Card className="gap-5">
                    <CardHeader className="gap-2 border-b border-border-soft-light dark:border-border-soft-dark pb-4">
                        <View className="flex-row items-start gap-3">
                            <View
                                accessibilityElementsHidden={true}
                                importantForAccessibility="no-hide-descendants"
                                className="w-11 h-11 rounded-xl bg-accent-light dark:bg-accent-dark items-center justify-center"
                                style={shadowBold(colorScheme)}
                            >
                                <KeyRound size={20} color={t.primaryForeground} />
                            </View>
                            <View className="flex-1 gap-1">
                                <CardTitle className="text-xl leading-snug">
                                    {PARITY_COPY.auth.passkeyPanel.title}
                                </CardTitle>
                                <Text className="text-sm font-open-sans-light leading-5 text-muted-foreground-light dark:text-muted-foreground-dark">
                                    {PARITY_COPY.auth.passkeyPanel.subtitle}
                                </Text>
                            </View>
                        </View>
                    </CardHeader>

                    <CardContent className="gap-2.5">
                        {!isConfirmingPhone && (
                            <>
                                <Pressable
                                    testID="auth-passkey-cta"
                                    variant="outline"
                                    onPress={handleDiscoverableSignIn}
                                    disabled={isLoading}
                                    accessibilityLabel={PARITY_COPY.auth.passkeyPanel.signInWithPasskey}
                                >
                                    <View className="flex-row items-center gap-2">
                                        <KeyRound size={16} color={t.foreground} />
                                        <Text className="text-foreground-light dark:text-foreground-dark text-sm font-open-sans-semibold">
                                            {PARITY_COPY.auth.passkeyPanel.signInWithPasskey}
                                        </Text>
                                    </View>
                                </Pressable>
                                <View className="flex-row items-center gap-3 py-1">
                                    <View className="flex-1 h-px bg-border-light dark:bg-border-dark" />
                                    <Text className="text-center text-xs font-open-sans-semibold uppercase tracking-widest text-muted-foreground-light dark:text-muted-foreground-dark">
                                        {PARITY_COPY.auth.passkeyPanel.orContinueWithPhone}
                                    </Text>
                                    <View className="flex-1 h-px bg-border-light dark:bg-border-dark" />
                                </View>
                            </>
                        )}

                        <FormField
                            testID="auth-phone-field"
                            label={PARITY_COPY.auth.passkeyPanel.phoneLabel}
                            value={PHONE_INPUT_TRANSFORMER.input(phone)}
                            onChangeText={(text) => {
                                setPhone(PHONE_INPUT_TRANSFORMER.output(text));
                                setError(null);
                            }}
                            placeholder={PARITY_COPY.auth.passkeyPanel.phonePlaceholder}
                            keyboardType="phone-pad"
                            autoComplete="tel"
                            textContentType="telephoneNumber"
                            maxLength={16}
                            error={!isConfirmingPhone ? (error ?? undefined) : undefined}
                            disabled={isConfirmingPhone || isLoading}
                            accessibilityLabel={PARITY_COPY.auth.passkeyPanel.phoneLabel}
                        />

                        <Text className="text-xs font-open-sans-light leading-5 text-muted-foreground-light dark:text-muted-foreground-dark -mt-2 mb-1">
                            {PARITY_COPY.auth.passkeyPanel.infoHint}
                        </Text>

                        {isConfirmingPhone && (
                            <FormField
                                testID="auth-code-field"
                                label={PARITY_COPY.auth.passkeyPanel.codeLabel}
                                value={code}
                                onChangeText={(text) => {
                                    setCode(text);
                                    setError(null);
                                }}
                                placeholder={PARITY_COPY.auth.passkeyPanel.codePlaceholder}
                                keyboardType="number-pad"
                                autoComplete="one-time-code"
                                textContentType="oneTimeCode"
                                maxLength={6}
                                error={isConfirmingPhone ? (error ?? undefined) : undefined}
                                disabled={isLoading}
                                accessibilityLabel={PARITY_COPY.auth.passkeyPanel.codeLabel}
                            />
                        )}

                        <Pressable
                            testID="auth-submit-cta"
                            variant="default"
                            onPress={handleSubmit}
                            disabled={isLoading}
                            accessibilityLabel={submitLabel}
                        >
                            <Text className="text-primary-foreground-light dark:text-primary-foreground-dark text-sm font-open-sans-semibold">
                                {submitLabel}
                            </Text>
                        </Pressable>

                        {isConfirmingPhone ? (
                            <Pressable
                                testID="auth-secondary-cta"
                                variant="outline"
                                onPress={handleCancel}
                                disabled={isLoading}
                                accessibilityLabel={PARITY_COPY.auth.passkeyPanel.cancelCta}
                            >
                                <Text className="text-foreground-light dark:text-foreground-dark text-sm font-open-sans-semibold">
                                    {PARITY_COPY.auth.passkeyPanel.cancelCta}
                                </Text>
                            </Pressable>
                        ) : (
                            <Pressable
                                testID="auth-secondary-cta"
                                variant="outline"
                                accessibilityRole="link"
                                onPress={handlePreviewSway}
                                accessibilityLabel={PARITY_COPY.auth.passkeyPanel.previewSway}
                            >
                                <Text className="text-foreground-light dark:text-foreground-dark text-sm font-open-sans-semibold">
                                    {PARITY_COPY.auth.passkeyPanel.previewSway}
                                </Text>
                            </Pressable>
                        )}

                        {isLoading && (
                            <View
                                testID="auth-loading-panel"
                                className="flex-row items-center gap-3 border border-border-light dark:border-border-dark rounded-xl px-4 py-3 bg-card-light dark:bg-card-dark"
                            >
                                <ActivityIndicator size="small" color={t.primary} />
                                <Text className="text-sm font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark">
                                    {PARITY_COPY.auth.passkeyPanel.workingOn}
                                </Text>
                            </View>
                        )}
                    </CardContent>
                </Card>

                <View className="gap-3 mt-5 mb-8" testID="auth-hero-features">
                    {HERO_ITEMS.map(({ title, description, Icon, testID }) => (
                        <Card key={title} className="px-4 py-4 gap-3">
                            <View className="flex-row items-start gap-3.5">
                                <View className="w-10 h-10 rounded-xl bg-surface-3-light dark:bg-surface-3-dark border border-border-soft-light dark:border-border-soft-dark items-center justify-center">
                                    <Icon size={18} color={t.primary} testID={testID} />
                                </View>
                                <View className="flex-1 gap-1">
                                    <CardTitle className="text-base">{title}</CardTitle>
                                    <Text className="text-sm font-open-sans-light leading-5 text-muted-foreground-light dark:text-muted-foreground-dark">
                                        {description}
                                    </Text>
                                </View>
                            </View>
                        </Card>
                    ))}
                </View>
            </ScrollView>
        </KeyboardAvoidingView>
    );
}

const HERO_ITEMS = [
    {
        title: "Cut through the noise",
        description: "Vote on the issues that matter, don't get bogged down by meaningless legislation.",
        Icon: Landmark,
        testID: "hero-icon-landmark",
    },
    {
        title: "Cast your vote",
        description: "Keep support and opposition obvious, fast, and readable on the first screen.",
        Icon: Vote,
        testID: "hero-icon-vote",
    },
    {
        title: "Reach the right people",
        description: "Use Sway to move from awareness to action without losing your place in the flow.",
        Icon: Megaphone,
        testID: "hero-icon-megaphone",
    },
] as const;
