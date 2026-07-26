import assert from "node:assert/strict";
import { isJobCancellable } from "../lib/documents/ui";

let failures = 0;

function check(name: string, fn: () => void) {
  try {
    fn();
    console.log(`PASS  ${name}`);
  } catch (err) {
    failures += 1;
    console.log(`FAIL  ${name} — ${(err as Error).message}`);
  }
}

check("isJobCancellable allows queued", () => {
  assert.equal(isJobCancellable("queued"), true);
});

check("isJobCancellable allows retry_scheduled", () => {
  assert.equal(isJobCancellable("retry_scheduled"), true);
});

check("isJobCancellable rejects claimed", () => {
  assert.equal(isJobCancellable("claimed"), false);
});

check("isJobCancellable rejects processing", () => {
  assert.equal(isJobCancellable("processing"), false);
});

check("isJobCancellable rejects succeeded", () => {
  assert.equal(isJobCancellable("succeeded"), false);
});

check("isJobCancellable rejects failed", () => {
  assert.equal(isJobCancellable("failed"), false);
});

check("isJobCancellable rejects cancelled", () => {
  assert.equal(isJobCancellable("cancelled"), false);
});

check("isJobCancellable rejects dead_lettered", () => {
  assert.equal(isJobCancellable("dead_lettered"), false);
});

if (failures > 0) {
  console.log(`\n${failures} test(s) failed.`);
  process.exit(1);
}
console.log("\nAll orchestration UI helper tests passed.");
