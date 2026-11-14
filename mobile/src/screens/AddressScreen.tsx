// @lat: [[mobile-auth-and-onboarding-flow#AddressScreen]]
import React, { useEffect, useState } from "react";
import { ActivityIndicator, Linking, Platform, ScrollView, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import type { NativeStackNavigationProp } from "@react-navigation/native-stack";
import Constants from "expo-constants";

import { apiClient } from "../api/client";
import * as legislatorCache from "../cache/legislatorCache";
import * as billCache from "../cache/billCache";
import { clearCapturedCategories } from "../hooks/useBills";
import { useSession } from "../hooks/useSession";
import { useUserProfile } from "../hooks/useUserProfile";
import AddressAutocomplete, { ParsedAddress } from "../components/AddressAutocomplete";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/Card";
import { FormField } from "../components/ui/FormField";
import { Pressable } from "../components/ui/Pressable";
import { PreferenceToggle } from "../components/PreferenceToggle";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import type { ProfileStackParamList } from "../navigation/types";

type Nav = NativeStackNavigationProp<ProfileStackParamList, "Address">;

interface AddressForm {
    street1: string;
    street2: string;
    city: string;
    region_code: string;
    postal_code: string;
    country: string;
    latitude: number | null;
    longitude: number | null;
    place_types: string[];
}

function emptyForm(): AddressForm {
    return {
        street1: "",
        street2: "",
        city: "",
        region_code: "",
        postal_code: "",
        country: "United States",
        latitude: null,
        longitude: null,
        place_types: [],
    };
}

function hasGooglePlacesKey(): boolean {
    const extra = Constants.expoConfig?.extra as
        | { googlePlacesApiKeyIOS?: string; googlePlacesApiKeyAndroid?: string }
        | undefined;
    return Boolean(Platform.OS === "ios" ? extra?.googlePlacesApiKeyIOS : extra?.googlePlacesApiKeyAndroid);
}

export default function AddressScreen() {
    const nav = useNavigation<Nav>();
    const { user, refresh } = useUserProfile();
    const { signOut } = useSession();
    const [form, setForm] = useState<AddressForm>(emptyForm());
    const [submitting, setSubmitting] = useState(false);
    const [error, setError] = useState<string | null>(null);
    // @lat: [[identity-and-access#Two voter-registration flags mean different things]]
    const [isVoterRegistrationAddressConfirmed, setIsVoterRegistrationAddressConfirmed] = useState(false);
    const autocompleteAvailable = hasGooglePlacesKey();
    const [showManual, setShowManual] = useState(!autocompleteAvailable);
    const [isRetrying, setIsRetrying] = useState(false);
    const [confirmingAddressSwitch, setConfirmingAddressSwitch] = useState(false);

    useEffect(() => {
        const a = user?.address;
        if (!a) return;
        setForm((f) => ({
            ...f,
            street1: a.street1 ?? "",
            street2: a.street2 ?? "",
            city: a.city ?? "",
            region_code: a.region_code ?? "",
            postal_code: a.postal_code ?? "",
            country: a.country ?? "United States",
        }));
    }, [user]);

    const onChange = (key: keyof AddressForm) => (val: string) => {
        setConfirmingAddressSwitch(false);
        setForm((f) => ({ ...f, [key]: val, latitude: null, longitude: null, place_types: [] }));
    };

    // @lat: [[identity-and-access#Registration is asynchronous by necessity]]
    const isOnboarding = user?.is_registration_complete !== true;
    const registrationStatus = (user as { registration_status?: string } | null)?.registration_status;
    const isProcessing = registrationStatus === "processing";
    const isFailed = registrationStatus === "failed";

    useEffect(() => {
        if (!isProcessing) return;
        const id = setInterval(() => {
            void refresh();
        }, 3000);
        return () => clearInterval(id);
    }, [isProcessing, refresh]);

    const submitForm = async (toSubmit: AddressForm) => {
        setError(null);
        setSubmitting(true);
        try {
            const street = [toSubmit.street1, toSubmit.street2].filter(Boolean).join(" ").trim();
            await apiClient.post("/sway_registration", {
                sway_registration: {
                    street,
                    city: toSubmit.city,
                    region_code: toSubmit.region_code,
                    postal_code: toSubmit.postal_code,
                    country: toSubmit.country,
                    latitude: toSubmit.latitude,
                    longitude: toSubmit.longitude,
                    place_types: toSubmit.place_types,
                    is_voter_registration_address_confirmed: isVoterRegistrationAddressConfirmed,
                    ...(!isOnboarding ? { confirm_deactivate_legislators: true } : {}),
                },
            });
            setIsRetrying(false);
            // @lat: [[mobile-sqlite-cache-design#Why address changes evict mobile SQLite caches]]
            clearCapturedCategories();
            await Promise.all([legislatorCache.clear().catch(() => {}), billCache.clear().catch(() => {})]);
            await refresh();
            if (nav.canGoBack()) nav.goBack();
        } catch (e) {
            setError(e instanceof Error ? e.message : "Could not update address.");
        } finally {
            setSubmitting(false);
            setConfirmingAddressSwitch(false);
        }
    };

    const handleSubmitPress = () => {
        if (!isOnboarding && !confirmingAddressSwitch) {
            setConfirmingAddressSwitch(true);
            return;
        }
        void submitForm(form);
    };

    const onAutocompleteSelect = (parsed: ParsedAddress) => {
        const next: AddressForm = {
            street1: parsed.street1,
            street2: parsed.street2,
            city: parsed.city,
            region_code: parsed.region_code,
            postal_code: parsed.postal_code,
            country: parsed.country || "United States",
            latitude: parsed.latitude,
            longitude: parsed.longitude,
            place_types: parsed.place_types,
        };
        setConfirmingAddressSwitch(false);
        setForm(next);
    };

    const hasPickedCoordinates = form.latitude != null && form.longitude != null;
    const savedAddress = user?.address;
    const matchesSavedAddress =
        savedAddress != null &&
        form.street1 === (savedAddress.street1 ?? "") &&
        form.street2 === (savedAddress.street2 ?? "") &&
        form.city === (savedAddress.city ?? "") &&
        form.region_code === (savedAddress.region_code ?? "") &&
        form.postal_code === (savedAddress.postal_code ?? "") &&
        form.country === (savedAddress.country ?? "United States");
    const canSubmit = form.street1.trim() !== "" && (isOnboarding || hasPickedCoordinates || !matchesSavedAddress);

    // @lat: [[mobile-auth-and-onboarding-flow#Why isOnboarding only changes wording]]
    const submitLabel = isOnboarding ? PARITY_COPY.address.complete.cta : PARITY_COPY.address.edit.saveCta;
    const cancelLabel = isOnboarding ? PARITY_COPY.address.complete.cancelCta : PARITY_COPY.address.edit.cancelCta;

    if (isProcessing) {
        return (
            <ScrollView
                className="flex-1 bg-dominant-light dark:bg-dominant-dark p-6"
                contentInsetAdjustmentBehavior="automatic"
                testID="address-screen"
            >
                <Card testID="address-processing">
                    <CardHeader>
                        <CardTitle>{PARITY_COPY.address.processing.title}</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <Text className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            {PARITY_COPY.address.processing.message}
                        </Text>
                        <ActivityIndicator className="mt-4" />
                        <View className="mt-4">
                            <Pressable
                                testID="address-processing-signout-cta"
                                variant="outline"
                                onPress={() => void signOut()}
                                accessibilityLabel="Cancel and sign out"
                            >
                                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    Cancel and sign out
                                </Text>
                            </Pressable>
                        </View>
                    </CardContent>
                </Card>
            </ScrollView>
        );
    }

    if (isFailed && !isRetrying) {
        return (
            <ScrollView
                className="flex-1 bg-dominant-light dark:bg-dominant-dark p-6"
                contentInsetAdjustmentBehavior="automatic"
                testID="address-screen"
            >
                <Card testID="address-failed">
                    <CardHeader>
                        <CardTitle>{PARITY_COPY.address.failed.title}</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <Text className="text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            {PARITY_COPY.address.failed.message}
                        </Text>
                        <View className="mt-4 gap-3">
                            <Pressable
                                testID="address-failed-retry-cta"
                                variant="default"
                                onPress={() => setIsRetrying(true)}
                                accessibilityLabel={PARITY_COPY.address.failed.retryCta}
                            >
                                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                    {PARITY_COPY.address.failed.retryCta}
                                </Text>
                            </Pressable>
                            <Pressable
                                testID="address-failed-signout-cta"
                                variant="outline"
                                onPress={() => void signOut()}
                                accessibilityLabel="Cancel and sign out"
                            >
                                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    Cancel and sign out
                                </Text>
                            </Pressable>
                        </View>
                    </CardContent>
                </Card>
            </ScrollView>
        );
    }

    return (
        <ScrollView
            className="flex-1 bg-dominant-light dark:bg-dominant-dark p-6"
            contentInsetAdjustmentBehavior="automatic"
            testID="address-screen"
            keyboardShouldPersistTaps="handled"
        >
            {isOnboarding && (
                <View testID="address-onboarding-heading" className="mb-6">
                    <Text className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {PARITY_COPY.address.complete.heading}
                    </Text>
                    <Text className="mt-1 text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                        {PARITY_COPY.address.complete.lead}
                    </Text>
                </View>
            )}

            {!isOnboarding && (
                <View className="mb-6">
                    <Text className="text-2xl font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        Address
                    </Text>
                    <Text className="mt-1 text-base font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                        {PARITY_COPY.address.switchConfirm.editLead}
                    </Text>
                </View>
            )}

            <Card className="mb-4">
                <CardContent>
                    {autocompleteAvailable && !showManual ? (
                        <View className="mb-4">
                            <AddressAutocomplete
                                initialValue={form.street1 ? `${form.street1}, ${form.city}` : ""}
                                onSelect={onAutocompleteSelect}
                                onError={setError}
                            />
                            <Pressable
                                testID="btn-edit-address-manually"
                                variant="ghost"
                                onPress={() => setShowManual(true)}
                                accessibilityLabel="Edit address fields manually"
                            >
                                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark underline">
                                    Edit address fields manually
                                </Text>
                            </Pressable>
                        </View>
                    ) : null}

                    {showManual ? (
                        <View>
                            {(
                                [
                                    ["street1", "Street address"],
                                    ["street2", "Apt / Unit (optional)"],
                                    ["city", "City"],
                                    ["region_code", "State"],
                                    ["postal_code", "ZIP code"],
                                    ["country", "Country"],
                                ] as const
                            ).map(([key, label]) => (
                                <FormField
                                    key={key}
                                    testID={`address-input-${key}`}
                                    label={label}
                                    value={form[key]}
                                    onChangeText={onChange(key)}
                                    accessibilityLabel={label}
                                />
                            ))}
                            {autocompleteAvailable ? (
                                <Pressable
                                    testID="btn-search-address-autocomplete"
                                    variant="ghost"
                                    onPress={() => setShowManual(false)}
                                    accessibilityLabel="Search for address"
                                >
                                    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark underline">
                                        Search for address
                                    </Text>
                                </Pressable>
                            ) : null}
                        </View>
                    ) : null}

                    {!showManual && hasPickedCoordinates ? (
                        <View
                            testID="selected-address-preview"
                            className="mb-4 p-3 border border-border-light dark:border-border-dark rounded-lg"
                        >
                            <Text className="text-xs font-open-sans-semibold text-muted-foreground-light dark:text-muted-foreground-dark mb-1 uppercase">
                                Selected address
                            </Text>
                            <Text className="text-sm font-open-sans-light text-foreground-light dark:text-foreground-dark">
                                {[
                                    form.street1,
                                    form.city,
                                    [form.region_code, form.postal_code].filter(Boolean).join(" "),
                                ]
                                    .filter(Boolean)
                                    .join(", ")}
                            </Text>
                        </View>
                    ) : null}

                    <PreferenceToggle
                        name="registered-voter-address-confirmation"
                        testID="registered-voter-address-confirmation"
                        label={PARITY_COPY.address.helper.registeredVoterConfirmation.label}
                        description={PARITY_COPY.address.helper.registeredVoterConfirmation.description}
                        value={isVoterRegistrationAddressConfirmed}
                        onValueChange={setIsVoterRegistrationAddressConfirmed}
                    />

                    {error ? (
                        <Text
                            testID="address-error"
                            className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark mb-4"
                        >
                            {error}
                        </Text>
                    ) : null}
                </CardContent>
            </Card>

            {!isOnboarding && confirmingAddressSwitch ? (
                <Card testID="address-switch-confirm" className="mb-4">
                    <CardContent className="gap-3">
                        <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                            {PARITY_COPY.address.switchConfirm.title}
                        </Text>
                        <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark">
                            {PARITY_COPY.address.switchConfirm.body}
                        </Text>
                        <View className="flex-row gap-3">
                            <Pressable
                                testID="address-confirm-deactivate-cta"
                                variant="default"
                                onPress={() => void submitForm(form)}
                                disabled={submitting}
                                accessibilityLabel={PARITY_COPY.address.switchConfirm.confirmCta}
                            >
                                <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                                    {PARITY_COPY.address.switchConfirm.confirmCta}
                                </Text>
                            </Pressable>
                            <Pressable
                                testID="address-cancel-deactivate-cta"
                                variant="outline"
                                onPress={() => setConfirmingAddressSwitch(false)}
                                disabled={submitting}
                                accessibilityLabel={PARITY_COPY.address.switchConfirm.cancelCta}
                            >
                                <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                                    {PARITY_COPY.address.switchConfirm.cancelCta}
                                </Text>
                            </Pressable>
                        </View>
                    </CardContent>
                </Card>
            ) : null}

            {/* @lat: [[identity-and-access#Registration is asynchronous by necessity#Mobile address actions follow registration status]] */}
            <View className="gap-4 mb-6">
                <Pressable
                    testID="address-submit-cta"
                    variant="default"
                    onPress={handleSubmitPress}
                    disabled={submitting || !canSubmit}
                    accessibilityLabel={submitLabel}
                >
                    {submitting ? (
                        <ActivityIndicator />
                    ) : (
                        <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                            {submitLabel}
                        </Text>
                    )}
                </Pressable>
                <Pressable
                    testID="address-cancel-cta"
                    variant="outline"
                    onPress={isOnboarding ? () => void signOut() : () => nav.goBack()}
                    accessibilityLabel={cancelLabel}
                    disabled={submitting}
                >
                    <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark">
                        {cancelLabel}
                    </Text>
                </Pressable>
            </View>

            {/* @lat: [[identity-and-access#Registration is asynchronous by necessity#Address help links retain platform behavior]] */}
            <View testID="address-helper-block" className="mt-2 mb-8">
                <View className="h-[1px] bg-border-light dark:bg-border-dark mb-4" />
                <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark mb-4">
                    {PARITY_COPY.address.helper.registeredVoterAdvisory}
                </Text>
                <Pressable
                    testID="address-register-to-vote"
                    variant="ghost"
                    onPress={() => void Linking.openURL(PARITY_COPY.address.helper.registerToVoteUrl)}
                    accessibilityLabel={PARITY_COPY.address.helper.registerToVote}
                    accessibilityRole="link"
                    style={{ alignItems: "flex-start", paddingLeft: 0 }}
                >
                    <Text className="text-sm font-open-sans-light text-accent-light dark:text-accent-dark underline">
                        {PARITY_COPY.address.helper.registerToVote}
                    </Text>
                </Pressable>
                <Pressable
                    testID="address-check-registration"
                    variant="ghost"
                    onPress={() => void Linking.openURL(PARITY_COPY.address.helper.checkRegistrationUrl)}
                    accessibilityLabel={PARITY_COPY.address.helper.checkRegistration}
                    accessibilityRole="link"
                    style={{ alignItems: "flex-start", paddingLeft: 0 }}
                >
                    <Text className="text-sm font-open-sans-light text-accent-light dark:text-accent-dark underline">
                        {PARITY_COPY.address.helper.checkRegistration}
                    </Text>
                </Pressable>
                <View className="mt-3">
                    <Text className="text-sm font-open-sans-light text-muted-foreground-light dark:text-muted-foreground-dark mb-1">
                        {PARITY_COPY.address.helper.viewOnGitHubIntro}
                    </Text>
                    <Pressable
                        testID="address-view-github"
                        variant="ghost"
                        onPress={() => void Linking.openURL(PARITY_COPY.address.helper.viewOnGitHubUrl)}
                        accessibilityLabel={PARITY_COPY.address.helper.viewOnGitHub}
                        accessibilityRole="link"
                        style={{ alignItems: "flex-start", paddingLeft: 0 }}
                    >
                        <Text className="text-sm font-open-sans-light text-accent-light dark:text-accent-dark underline">
                            {PARITY_COPY.address.helper.viewOnGitHub}
                        </Text>
                    </Pressable>
                </View>
            </View>
        </ScrollView>
    );
}
