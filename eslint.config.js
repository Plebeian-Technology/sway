import globals from "globals";
import tseslint from "typescript-eslint";
import reactRefresh from "eslint-plugin-react-refresh";
import rulesOfHooks from "eslint-plugin-react-hooks";
import eslintImport from "eslint-plugin-import";
import typescriptParser from "@typescript-eslint/parser";
import typescriptEslint from "@typescript-eslint/eslint-plugin";

export default [
    // pluginJs.configs.recommended,
    ...tseslint.configs.recommended,
    // ...tseslint.configs.stylistic,
    // pluginReactConfig,
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

        plugins: {
            "@typescript-eslint": typescriptEslint,
            "react-refresh": reactRefresh,
            "react-hooks": rulesOfHooks,
            import: eslintImport,
        },
    },
    {
        settings: {
            react: {
                version: "detect",
            },
        },
    },
    {
        rules: {
            "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],

            // "react-hooks/rules-of-hooks": "error",
            // "react-hooks/exhaustive-deps": "warn",
            ...rulesOfHooks.configs.recommended.rules,

            // "react/prop-types": "off",
            // "react/react-in-jsx-scope": "off",
            // "react/jsx-no-target-blank": "warn",
            // "react/display-name": "off",

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
            "no-unused-vars": "off",
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
            "@typescript-eslint/no-explicit-any": "off",
            "@typescript-eslint/no-unused-vars": [
                "warn", // or "error"
                {
                    argsIgnorePattern: "^_",
                    varsIgnorePattern: "^_",
                    caughtErrorsIgnorePattern: "^_",
                },
            ],
        },
    },
    {
        ignores: [
            "app/assets/",
            "app/views/*",
            "config/",
            "docker/",
            "sorbet/",
            "node_modules/",
            "log/",
            "lib/",
            "db/",
            "bin/",
            "public/",
            "spec/",
            "storage/",
            "tf/",
            "tmp/",
            "vendor/",
            "eslint.config.js",
            "vite*",
        ],
    },
];
