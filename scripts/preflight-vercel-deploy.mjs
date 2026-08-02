#!/usr/bin/env node
/**
 * Fails loudly (non-zero exit) unless run from the repository root with
 * the correct Vercel project linked. Run this before any `vercel` CLI
 * command — see docs/operations/vercel-preview-deployment.md for the
 * real, repeated mistake this guards against: running `vercel` from
 * `apps/web/` silently creates/deploys a second, wrong project (it
 * cannot see the workspace root, so `@noor/ui` fails to resolve).
 *
 * Purely a local file/cwd check — never calls the Vercel API, never
 * reads credentials.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const EXPECTED_PROJECT_NAME = "noor";
const projectFilePath = resolve(process.cwd(), ".vercel", "project.json");

if (!existsSync(projectFilePath)) {
  console.error(
    `FAIL: no .vercel/project.json found at "${projectFilePath}".\n` +
      "Run this script (and every `vercel` command) from the repository root, not a subdirectory."
  );
  process.exit(1);
}

let project;
try {
  project = JSON.parse(readFileSync(projectFilePath, "utf-8"));
} catch (err) {
  console.error(`FAIL: could not parse ${projectFilePath}: ${err.message}`);
  process.exit(1);
}

if (project.projectName !== EXPECTED_PROJECT_NAME) {
  console.error(
    `FAIL: linked Vercel project is "${project.projectName}", expected "${EXPECTED_PROJECT_NAME}".\n` +
      "Do not deploy — this would target the wrong project."
  );
  process.exit(1);
}

console.log(`OK: repository root, linked to Vercel project "${project.projectName}". Safe to deploy.`);
