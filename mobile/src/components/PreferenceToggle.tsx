// @lat: [[mobile-org-membership-components-design#PreferenceToggle]]
import React from "react";
import { Switch } from "react-native";

import { ListRow } from "./ui/ListRow";

export interface PreferenceToggleProps {
    name: string;
    label: string;
    description?: string;
    value: boolean;
    onValueChange: (next: boolean) => void;
    // @lat: [[mobile-org-membership-components-design#PreferenceToggle#About disabled]]
    disabled?: boolean;
    testID?: string;
}

export function PreferenceToggle({
    name,
    label,
    description,
    value,
    onValueChange,
    disabled,
    testID,
}: PreferenceToggleProps) {
    return (
        <ListRow
            label={label}
            description={description}
            testID={testID ?? `pref-toggle-${name}`}
            accessibilityLabel={label}
            rightSlot={
                <Switch
                    value={value}
                    onValueChange={onValueChange}
                    disabled={disabled}
                    accessibilityLabel={label}
                    accessibilityState={{ checked: value, disabled: !!disabled }}
                    testID={`pref-switch-${name}`}
                />
            }
        />
    );
}

export default PreferenceToggle;
