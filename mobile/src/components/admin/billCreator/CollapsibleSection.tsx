// @lat: [[mobile-bill-creator#Sections#The pipeline read-only panels]]
import React, { useState } from "react";
import { Text, View } from "react-native";

import { Pressable } from "../../ui/Pressable";

interface CollapsibleSectionProps {
    testID: string;
    title: string;
    children: React.ReactNode;
}

const labelText = "text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark";

const CollapsibleSection: React.FC<CollapsibleSectionProps> = ({ testID, title, children }) => {
    const [open, setOpen] = useState(false);
    return (
        <View testID={testID} className="px-4 mt-6 gap-2">
            <Pressable
                testID={`${testID}-toggle`}
                variant="outline"
                accessibilityState={{ expanded: open }}
                onPress={() => setOpen(!open)}
            >
                <Text className={labelText}>{title}</Text>
            </Pressable>
            {open ? children : null}
        </View>
    );
};

export default CollapsibleSection;
