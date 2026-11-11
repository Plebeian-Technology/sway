// @lat: [[mobile-dev-primitive-gallery-screen#Visibility]]
import React, { useState } from "react";
import { ScrollView, Text, View } from "react-native";
import { ThemeProvider } from "../../theme/ThemeProvider";
import { swayTokens } from "../../theme/tokens";
import { Card, CardContent, CardHeader, CardTitle } from "../../components/ui/Card";
import { Pressable } from "../../components/ui/Pressable";
import { EmptyState } from "../../components/ui/EmptyState";
import { ListRow } from "../../components/ui/ListRow";
import { FormField } from "../../components/ui/FormField";

const MODES = ["light", "dark"] as const;
type Mode = (typeof MODES)[number];

function GallerySection({ mode }: { mode: Mode }) {
    const [fieldValue, setFieldValue] = useState("");
    const heading = mode === "light" ? "SWAY LIGHT" : "SWAY DARK";
    return (
        <ThemeProvider initialMode={mode}>
            <View
                testID={`gallery-section-${mode}`}
                // @lat: [[mobile-dev-primitive-gallery-screen#Why two providers instead of one toggle]]
                style={{ backgroundColor: swayTokens[mode].background, padding: 16 }}
            >
                <Text
                    testID={`gallery-heading-${mode}`}
                    className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-4"
                >
                    {heading}
                </Text>

                <View className="mb-6">
                    <Card testID={`gallery-card-${mode}`}>
                        <CardHeader>
                            <CardTitle>Card title</CardTitle>
                        </CardHeader>
                        <CardContent>
                            <Text className="text-base font-open-sans-light text-card-foreground-light dark:text-card-foreground-dark">
                                Card content
                            </Text>
                        </CardContent>
                    </Card>
                </View>

                <View className="mb-6">
                    <Pressable
                        testID={`gallery-pressable-${mode}`}
                        onPress={() => undefined}
                        accessibilityLabel="Primary action"
                    >
                        <Text className="text-sm font-open-sans-semibold text-primary-foreground-light dark:text-primary-foreground-dark">
                            Primary action
                        </Text>
                    </Pressable>
                </View>

                <View className="mb-6">
                    <EmptyState
                        testID={`gallery-empty-${mode}`}
                        title="No results"
                        body="Nothing here yet."
                        ctaLabel="Refresh List"
                        onCtaPress={() => undefined}
                    />
                </View>

                <View className="mb-6">
                    <ListRow testID={`gallery-row-${mode}`} label="Row label" onPress={() => undefined} />
                </View>

                {/* @lat: [[mobile-dev-primitive-gallery-screen#PrimitiveGalleryScreen]] */}
                <View className="mb-6">
                    <FormField
                        testID={`gallery-field-${mode}`}
                        label="Field label"
                        value={fieldValue}
                        onChangeText={setFieldValue}
                        error={fieldValue.length === 0 ? "This field is required." : undefined}
                    />
                </View>
            </View>
        </ThemeProvider>
    );
}

export function PrimitiveGalleryScreen() {
    return (
        <ScrollView testID="primitives-gallery">
            {MODES.map((mode) => (
                <GallerySection key={mode} mode={mode} />
            ))}
        </ScrollView>
    );
}

export default PrimitiveGalleryScreen;
