const defaults = require("../../.eslintrc.js");

module.exports = {
    ...defaults,
    root: false,
    extends: [...defaults.extends, "plugin:react-hooks/recommended"],
    rules: {
        ...defaults.rules,
        "react-hooks/rules-of-hooks": "error", // Checks rules of Hooks
        "react-hooks/exhaustive-deps": "warn", // Checks effect dependencies
    },
    parserOptions: {
        project: "./tsconfig.json",
        sourceType: "module",
    },
};
