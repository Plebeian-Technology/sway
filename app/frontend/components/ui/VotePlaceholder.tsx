import React from "react";
import { Lock } from "lucide-react"; // Or another appropriate icon

interface IProps {
    message?: string;
}

const VotePlaceholder: React.FC<IProps> = ({ message = "Data hidden to protect voter privacy" }) => {
    return (
        <div className="flex items-center gap-2 text-muted-foreground bg-muted p-2 rounded text-sm italic">
            <Lock className="w-4 h-4" />
            <span>{message}</span>
        </div>
    );
};

export default VotePlaceholder;
