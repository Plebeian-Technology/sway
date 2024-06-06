import globals from "globals";
import pluginJs from "@eslint/js";
import tseslint from "typescript-eslint";
import react from "eslint-plugin-react/configs/recommended.js";
import reactRefresh from "eslint-plugin-react-refresh";
import rulesOfHooks from "eslint-plugin-react-hooks";
import eslintImport from "eslint-plugin-import";
import typescriptParser from "@typescript-eslint/parser";
import typescriptEslint from "@typescript-eslint/eslint-plugin";

export default [
    // pluginJs.configs.recommended,
    // ...tseslint.configs.recommended,
    // ...tseslint.configs.stylistic,
    react,
    {
        languageOptions: {
            globals: {
                ...globals.serviceworker,
                ...globals.browser,
            },
            parserOptions: {
                parser: typescriptParser,
                project: "tsconfig.json",
                ecmaVersion: "latest",
                sourceType: "module",
                ecmaFeatures: {
                    jsx: true,
                },
            },
        },

        ignores: ["**/*", "!app/frontend/"],

        settings: {
            react: {
                version: "detect",
            },
        },

        plugins: {
            "@typescript-eslint": typescriptEslint,
            "react-refresh": reactRefresh,
            "react-hooks": rulesOfHooks,
            import: eslintImport,
        },

        rules: {
            "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],

            "react-hooks/rules-of-hooks": "error",
            "react-hooks/exhaustive-deps": "warn",

            "constructor-super": "error",
            "no-restricted-globals": "error",
            eqeqeq: ["warn", "always"],
            "import/no-deprecated": "off",
            "import/no-extraneous-dependencies": "error",
            "import/no-unassigned-import": "off",
            "no-cond-assign": "error",
            "no-duplicate-case": "error",
            "no-duplicate-imports": "error",
            "no-empty": [
                "error",
                {
                    allowEmptyCatch: true,
                },
            ],
            "no-invalid-this": "error",
            "no-new-wrappers": "error",
            "no-param-reassign": "error",
            "no-redeclare": "error",
            "no-sequences": "error",
            "no-shadow": [
                "error",
                {
                    hoist: "all",
                },
            ],
            "no-throw-literal": "error",
            "no-unsafe-finally": "error",
            "no-unused-labels": "error",
            "no-var": "warn",
            "no-void": "error",
            "prefer-const": "warn",

            "@typescript-eslint/ban-ts-comment": "warn",

            "react/prop-types": "off",
            "react/react-in-jsx-scope": "off",
            "react/jsx-no-target-blank": "warn",
            "react/display-name": "off",
        },
    },
];
