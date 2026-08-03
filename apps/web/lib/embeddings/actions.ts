"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { toEmbeddingError } from "@/lib/embeddings/errors";
import { createEmbeddingJobSchema, cancelEmbeddingRunSchema } from "@/lib/embeddings/schemas";

function text(formData: FormData, key: string): string {
  return String(formData.get(key) ?? "").trim();
}

function withError(path: string, message: string): never {
  redirect(`${path}?error=${encodeURIComponent(message)}`);
}

const QUEUE_PATH = "/quality/embeddings";
function runDetailPath(runId: string): string {
  return `/quality/embeddings/runs/${runId}`;
}

export async function createEmbeddingJobAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.DOCUMENT_EMBEDDINGS_CREATE);
  const parsed = createEmbeddingJobSchema.safeParse({
    sourceDocumentId: text(formData, "sourceDocumentId"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "A valid source document ID is required.");

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_document_embedding_job", {
    p_source_document_id: parsed.data.sourceDocumentId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(QUEUE_PATH, toEmbeddingError(error).message);

  revalidatePath(QUEUE_PATH);
  redirect(QUEUE_PATH);
}

export async function cancelEmbeddingRunAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.DOCUMENT_EMBEDDINGS_CANCEL);
  const parsed = cancelEmbeddingRunSchema.safeParse({
    embeddingRunId: text(formData, "embeddingRunId"),
    reason: text(formData, "reason"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "A reason is required.");
  const returnTo = runDetailPath(parsed.data.embeddingRunId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_document_embedding_run", {
    p_embedding_run_id: parsed.data.embeddingRunId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toEmbeddingError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}
