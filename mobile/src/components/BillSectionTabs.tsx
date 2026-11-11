// @lat: [[mobile-bill-surface-components-design#BillSectionTabs]]
import React, { useState } from "react";
import { View } from "react-native";
import { BroadsideTabStrip } from "./BroadsideTabStrip";

interface IProps {
    bill: React.ReactNode;
    votes: React.ReactNode;
    summaries: React.ReactNode;
    testID?: string;
}

const TABS = [
    { key: "bill", label: "Bill" },
    { key: "votes", label: "Votes" },
    { key: "summaries", label: "Summaries" },
];

const BillSectionTabs: React.FC<IProps> = ({ bill, votes, summaries, testID }) => {
    const [activeKey, setActiveKey] = useState("bill");
    const sections: Record<string, React.ReactNode> = { bill, votes, summaries };
    return (
        <View testID={testID}>
            <BroadsideTabStrip tabs={TABS} activeKey={activeKey} onChange={setActiveKey} />
            {sections[activeKey]}
        </View>
    );
};

export default BillSectionTabs;
