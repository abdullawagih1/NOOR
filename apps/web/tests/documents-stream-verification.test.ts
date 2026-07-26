import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { computeFileFactsFromStream } from "../lib/documents/streamVerification";

let failures = 0;

function check(name: string, fn: () => void | Promise<void>) {
  return (async () => {
    try {
      await fn();
      console.log(`PASS  ${name}`);
    } catch (err) {
      failures += 1;
      console.log(`FAIL  ${name} — ${(err as Error).message}`);
    }
  })();
}

/** A stream that yields `chunks` one at a time via `pull`, tracking how many times it was actually pulled. */
function makeStream(chunks: Buffer[]): { stream: ReadableStream<Uint8Array>; pullCount: () => number } {
  let i = 0;
  let pulls = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (i >= chunks.length) {
        controller.close();
        return;
      }
      pulls += 1;
      controller.enqueue(chunks[i]);
      i += 1;
    },
  });
  return { stream, pullCount: () => pulls };
}

async function main() {
  await check("streams a small valid PDF split across multiple chunks and matches a full-buffer hash", async () => {
    const content = Buffer.from("%PDF-1.4\nSome synthetic guideline content spread across several chunks.\n%%EOF\n");
    const chunkSize = 7;
    const chunks: Buffer[] = [];
    for (let i = 0; i < content.byteLength; i += chunkSize) chunks.push(content.subarray(i, i + chunkSize));
    assert.ok(chunks.length > 3, "test fixture should actually span multiple chunks");

    const { stream, pullCount } = makeStream(chunks);
    const facts = await computeFileFactsFromStream(stream, 10_000_000);

    const expectedSha256 = createHash("sha256").update(content).digest("hex");
    assert.equal(facts.sizeBytes, content.byteLength);
    assert.equal(facts.sha256, expectedSha256);
    assert.equal(facts.signatureValid, true);
    assert.equal(facts.oversized, false);
    assert.ok(facts.chunksRead > 1, "should have actually consumed more than one chunk");
    assert.equal(pullCount(), chunks.length, "should have pulled every chunk of a within-limit stream");
  });

  await check("detects a non-PDF signature", async () => {
    const content = Buffer.from("PK\x03\x04 not a pdf, looks like a zip");
    const { stream } = makeStream([content]);
    const facts = await computeFileFactsFromStream(stream, 10_000_000);
    assert.equal(facts.signatureValid, false);
  });

  await check("handles an empty stream", async () => {
    const { stream } = makeStream([]);
    const facts = await computeFileFactsFromStream(stream, 10_000_000);
    assert.equal(facts.sizeBytes, 0);
    assert.equal(facts.signatureValid, false);
  });

  await check("aborts early on an oversized stream without reading every chunk", async () => {
    const chunk = Buffer.from("%PDF-" + "x".repeat(10)); // 15 bytes per chunk
    const chunks = Array.from({ length: 50 }, () => Buffer.from(chunk));
    const { stream, pullCount } = makeStream(chunks);

    const facts = await computeFileFactsFromStream(stream, 40); // limit well under the full 750 bytes

    assert.equal(facts.oversized, true);
    assert.equal(facts.sha256, null, "a partial hash over a truncated file must not be reported as a real checksum");
    assert.ok(pullCount() < chunks.length, `expected early abort, but all ${chunks.length} chunks were pulled`);
    assert.ok(pullCount() <= 5, `expected to stop within a few chunks of the 40-byte limit, pulled ${pullCount()}`);
  });

  await check("reports the exact byte count for a within-limit stream", async () => {
    const { stream } = makeStream([Buffer.from("%PDF-1.4 short file")]);
    const facts = await computeFileFactsFromStream(stream, 10_000_000);
    assert.equal(facts.sizeBytes, Buffer.from("%PDF-1.4 short file").byteLength);
    assert.equal(facts.oversized, false);
  });

  if (failures > 0) {
    console.log(`\n${failures} test(s) failed.`);
    process.exit(1);
  }
  console.log("\nAll streaming file-verification tests passed.");
}

main();
