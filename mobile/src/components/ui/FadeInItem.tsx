// @lat: [[mobile-shared-primitives-design#ui/FadeInItem]]
import React from "react";
import type { StyleProp, ViewStyle } from "react-native";
import Animated, { FadeInDown } from "react-native-reanimated";

export interface FadeInItemProps {
    children: React.ReactNode;
    index?: number;
    stepMs?: number;
    maxSteps?: number;
    style?: StyleProp<ViewStyle>;
    testID?: string;
}

export function FadeInItem({ children, index = 0, stepMs = 50, maxSteps = 6, style, testID }: FadeInItemProps) {
    const delayMs = Math.min(index, maxSteps) * stepMs;
    return (
        <Animated.View testID={testID} style={style} entering={FadeInDown.duration(280).delay(delayMs)}>
            {children}
        </Animated.View>
    );
}

export default FadeInItem;
