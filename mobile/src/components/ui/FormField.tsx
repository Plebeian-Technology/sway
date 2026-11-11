// @lat: [[mobile-shared-primitives-design#ui/FormField]]
import React, { useEffect, useRef, useState } from "react";
import { Text, TextInput, View, type KeyboardTypeOptions, type TextInputProps } from "react-native";

export interface FormFieldProps {
    label: string;
    value: string;
    onChangeText: (text: string) => void;
    placeholder?: string;
    error?: string;
    disabled?: boolean;
    secureTextEntry?: boolean;
    keyboardType?: KeyboardTypeOptions;
    autoComplete?: TextInputProps["autoComplete"];
    textContentType?: TextInputProps["textContentType"];
    testID?: string;
    accessibilityLabel?: string;
    maxLength?: number;
}

export function FormField({
    label,
    value,
    onChangeText,
    placeholder,
    error,
    disabled = false,
    secureTextEntry,
    keyboardType,
    autoComplete,
    textContentType,
    testID,
    accessibilityLabel,
    maxLength,
}: FormFieldProps) {
    const [focused, setFocused] = useState(false);
    const mounted = useRef(true);
    useEffect(() => {
        return () => {
            mounted.current = false;
        };
    }, []);
    const borderClass = error
        ? "border-destructive-light dark:border-destructive-dark"
        : focused
          ? "border-ring-light dark:border-ring-dark"
          : "border-border-light dark:border-border-dark";
    return (
        <View testID={testID} className="mb-4">
            <Text className="text-sm font-open-sans-semibold text-foreground-light dark:text-foreground-dark mb-2">
                {label}
            </Text>
            <TextInput
                value={value}
                onChangeText={onChangeText}
                onFocus={() => {
                    if (mounted.current) setFocused(true);
                }}
                onBlur={() => {
                    if (mounted.current) setFocused(false);
                }}
                placeholder={placeholder}
                editable={!disabled}
                secureTextEntry={secureTextEntry}
                keyboardType={keyboardType}
                autoComplete={autoComplete}
                textContentType={textContentType}
                accessibilityLabel={accessibilityLabel ?? label}
                accessibilityState={{ disabled }}
                testID={testID ? `${testID}-input` : undefined}
                className={`border ${borderClass} rounded-md px-4 py-3 bg-input-light dark:bg-input-dark font-open-sans-light text-foreground-light dark:text-foreground-dark`}
                style={{ minHeight: 44, opacity: disabled ? 0.5 : 1 }}
                maxLength={maxLength}
            />
            {error ? (
                <Text
                    testID={testID ? `${testID}-error` : "form-field-error"}
                    className="text-sm font-open-sans-semibold text-destructive-light dark:text-destructive-dark mt-1"
                >
                    {error}
                </Text>
            ) : null}
        </View>
    );
}
