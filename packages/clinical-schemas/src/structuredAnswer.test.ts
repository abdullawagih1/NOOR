import { parseStructuredAnswer } from "./structuredAnswer";

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

function expectThrow(fn: () => void) {
  let threw = false;
  try {
    fn();
  } catch {
    threw = true;
  }
  if (!threw) throw new Error("expected an error to be thrown, but none was");
}

const validAnswer = {
  query_id: "11111111-1111-1111-1111-111111111111",
  scope_status: "within_scope",
  evidence_status: "sufficient",
  answer_summary: "Guideline-grounded summary.",
  recommendations: [
    {
      statement: "Confirm diagnosis before initiating therapy.",
      evidence_ids: ["E1"],
      limitations: [],
    },
  ],
  warnings: [],
  missing_information: [],
  citations: [
    {
      evidence_id: "E1",
      document_id: "22222222-2222-2222-2222-222222222222",
      document_title: "Adult Hypertension Guideline",
      document_version: "1.0",
      section_title: "Diagnosis",
      page_number: 12,
      quoted_excerpt: "Diagnosis requires two elevated readings.",
    },
  ],
  requires_clinician_review: true,
};

check("valid answer parses successfully", () => {
  const result = parseStructuredAnswer(validAnswer);
  if (result.citations.length !== 1) throw new Error("citation not preserved");
});

check("insufficient evidence with recommendations fails closed", () => {
  expectThrow(() =>
    parseStructuredAnswer({
      ...validAnswer,
      evidence_status: "insufficient",
    })
  );
});

check("out-of-scope with recommendations fails closed", () => {
  expectThrow(() =>
    parseStructuredAnswer({
      ...validAnswer,
      scope_status: "out_of_scope",
    })
  );
});

check("recommendation citing a non-existent evidence_id fails closed", () => {
  expectThrow(() =>
    parseStructuredAnswer({
      ...validAnswer,
      recommendations: [
        {
          statement: "Unsupported statement.",
          evidence_ids: ["E-does-not-exist"],
          limitations: [],
        },
      ],
    })
  );
});

check("missing required field fails schema validation", () => {
  const { query_id, ...withoutQueryId } = validAnswer;
  expectThrow(() => parseStructuredAnswer(withoutQueryId));
});

check("requires_clinician_review must be literal true", () => {
  expectThrow(() =>
    parseStructuredAnswer({ ...validAnswer, requires_clinician_review: false })
  );
});

if (failures > 0) {
  console.error(`\n${failures} test(s) failed.`);
  process.exit(1);
} else {
  console.log("\nAll clinical-schemas tests passed.");
}
