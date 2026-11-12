// Summary: the code checker's settings: Next.js's recommended rules, and
// folders it should skip.
//
import { defineConfig, globalIgnores } from "eslint/config"; // Tools to write the settings and list folders to skip.
import nextVitals from "eslint-config-next/core-web-vitals"; // Next.js's rules for speed and good practice.
import nextTs from "eslint-config-next/typescript"; // Next.js's rules for TypeScript.

const eslintConfig = defineConfig([ // The settings:
  ...nextVitals, // the Next.js speed rules,
  ...nextTs, // the TypeScript rules,
  // Override default ignores of eslint-config-next.
  globalIgnores([ // folders and files to skip:
    // Default ignores of eslint-config-next:
    ".next/**", // the built app,
    "out/**", // exported pages,
    "build/**", // build output,
    "next-env.d.ts", // and a file Next.js writes itself.
  ]), // End of the list.
]); // End of the settings.

export default eslintConfig; // Gives the settings to the checker.
