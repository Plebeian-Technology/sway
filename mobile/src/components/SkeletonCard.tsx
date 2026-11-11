// @lat: [[mobile-shared-primitives-design#SkeletonCard]]
import React, { useEffect } from "react";
import Animated, { useSharedValue, useAnimatedStyle, withRepeat, withTiming, Easing } from "react-native-reanimated";

export interface SkeletonCardProps {
    heightClass?: string;
    testID?: string;
}

export function SkeletonCard({ heightClass = "h-24", testID = "skeleton-card" }: SkeletonCardProps) {
    const op = useSharedValue(0.4);
    useEffect(() => {
        op.value = withRepeat(withTiming(0.9, { duration: 800, easing: Easing.inOut(Easing.ease) }), -1, true);
    }, [op]);
    const animatedStyle = useAnimatedStyle(() => ({ opacity: op.value }));
    return (
        <Animated.View
            accessibilityLabel="Loading"
            accessibilityRole="none"
            testID={testID}
            className={`${heightClass} bg-muted-foreground-light/30 dark:bg-muted-foreground-dark/30 rounded-lg`}
            style={animatedStyle}
        />
    );
}

export default SkeletonCard;
