import { z } from "zod";

/**
 * The Noor V1 structured clinical answer contract (Execution Plan §11,
 * Master Prompt §12). This is the ONLY shape the AI Gateway is allowed to
 * return to the application layer. Schema-invalid output must fail closed
 * — see docs/api/contracts.md — never be silently displayed or "repaired"
 * by string manipulation.
 */

export const evidenceStatusSchema = z.enum([
  "sufficient",
  "partial",
  "insufficient",
  "conflicting",
]);

export const scopeStatusSchema = z.enum(["within_scope", "out_of_scope"]);

export const citationSchema = z.object({
  evidence_id: z.string().min(1),
  document_id: z.string().uuid(),
  document_title: z.string().min(1),
  document_version: z.string().min(1),
  section_title: z.string().min(1),
  page_number: z.number().int().positive(),
  quoted_excerpt: z.string().min(1).max(2000),
});

export const recommendationSchema = z.object({
  statement: z.string().min(1),
  evidence_ids: z.array(z.string().min(1)).min(1),
  limitations: z.array(z.string()).default([]),
});

export const structuredAnswerSchema = z.object({
  query_id: z.string().uuid(),
  scope_status: scopeStatusSchema,
  evidence_status: evidenceStatusSchema,
  answer_summary: z.string().min(1),
  recommendations: z.array(recommendationSchema),
  warnings: z.array(z.string()).default([]),
  missing_information: z.array(z.string()).default([]),
  citations: z.array(citationSchema),
  requires_clinician_review: z.literal(true),
});

export type StructuredAnswer = z.infer<typeof structuredAnswerSchema>;
export type Citation = z.infer<typeof citationSchema>;
export type Recommendation = z.infer<typeof recommendationSchema>;

/**
 * Cross-field safety invariants that zod's shape validation alone cannot
 * express. Both must hold before an answer is displayed (Master Prompt §13,
 * §12: "Never silently display malformed output.").
 */
export function assertAnswerSafetyInvariants(answer: StructuredAnswer): void {
  if (answer.evidence_status === "insufficient" && answer.recommendations.length > 0) {
    throw new Error(
      "Safety invariant violated: insufficient evidence must not carry recommendations."
    );
  }

  if (answer.scope_status === "out_of_scope" && answer.recommendations.length > 0) {
    throw new Error(
      "Safety invariant violated: out-of-scope questions must not carry recommendations."
    );
  }

  for (const rec of answer.recommendations) {
    for (const evidenceId of rec.evidence_ids) {
      const hasCitation = answer.citations.some((c) => c.evidence_id === evidenceId);
      if (!hasCitation) {
        throw new Error(
          `Safety invariant violated: recommendation references evidence_id "${evidenceId}" with no matching citation.`
        );
      }
    }
  }
}

/**
 * Parses and validates a raw AI Gateway response. Throws on any violation —
 * callers must treat a thrown error as "fail closed" (refuse to answer),
 * never attempt to partially render the result.
 */
export function parseStructuredAnswer(raw: unknown): StructuredAnswer {
  const parsed = structuredAnswerSchema.parse(raw);
  assertAnswerSafetyInvariants(parsed);
  return parsed;
}
