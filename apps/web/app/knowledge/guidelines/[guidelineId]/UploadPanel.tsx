"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { createGuidelineUploadSessionAction, completeGuidelineUploadAction } from "@/lib/documents/actions";
import { MAX_UPLOAD_SIZE_BYTES } from "@/lib/documents/config";
import { Alert } from "@noor/ui";

type UploadState = "idle" | "uploading" | "verifying" | "registered" | "rejected" | "error";

const STATE_LABEL: Record<UploadState, string> = {
  idle: "Ready — PDF only, up to 50 MB.",
  uploading: "Uploading…",
  verifying: "Verifying…",
  registered: "Registered.",
  rejected: "Rejected.",
  error: "Error.",
};

/**
 * Client-side upload flow: select -> createGuidelineUploadSessionAction
 * (server creates the DB records + signed Storage authorization) ->
 * uploadToSignedUrl (direct browser-to-Storage PUT, RLS-authorized by the
 * caller's own session, never a service-role key) ->
 * completeGuidelineUploadAction (server independently re-fetches the
 * object and verifies it — this component never asserts verification
 * itself, only reports what the server decided).
 */
export function UploadPanel({ guidelineVersionId }: { guidelineVersionId: string }) {
  const [state, setState] = useState<UploadState>("idle");
  const [message, setMessage] = useState<string | null>(null);
  const router = useRouter();

  async function handleFileSelected(file: File) {
    setMessage(null);

    if (!file.name.toLowerCase().endsWith(".pdf")) {
      setState("error");
      setMessage("Only .pdf files are supported.");
      return;
    }
    if (file.size <= 0) {
      setState("error");
      setMessage("File must not be empty.");
      return;
    }
    if (file.size > MAX_UPLOAD_SIZE_BYTES) {
      setState("error");
      setMessage(`File exceeds the ${MAX_UPLOAD_SIZE_BYTES / (1024 * 1024)} MB limit.`);
      return;
    }

    setState("uploading");
    try {
      const auth = await createGuidelineUploadSessionAction({
        guidelineVersionId,
        filename: file.name,
        declaredMediaType: "application/pdf",
        expectedSizeBytes: file.size,
      });

      const supabase = createClient();
      const { error: uploadError } = await supabase.storage
        .from(auth.storageBucket)
        .uploadToSignedUrl(auth.storagePath, auth.signedUploadToken, file);
      if (uploadError) {
        throw new Error(uploadError.message);
      }

      setState("verifying");
      const result = await completeGuidelineUploadAction(auth.uploadSessionId);

      if (result.documentStatus === "registered") {
        setState("registered");
        setMessage("Document verified and registered. A processing job has been queued.");
      } else {
        setState("rejected");
        setMessage("The upload was not accepted — see the document list below for the reason.");
      }
      router.refresh();
    } catch (err) {
      setState("error");
      setMessage(err instanceof Error ? err.message : "Upload failed. Please try again.");
    }
  }

  const busy = state === "uploading" || state === "verifying";

  return (
    <div className="flex flex-col gap-sm">
      <label className="flex flex-col gap-xxs">
        <span className="text-sm font-medium text-body">Upload source PDF</span>
        <input
          type="file"
          accept="application/pdf,.pdf"
          disabled={busy}
          aria-describedby="upload-status"
          onChange={(e) => {
            const file = e.target.files?.[0];
            e.target.value = "";
            if (file) void handleFileSelected(file);
          }}
          className="text-sm text-body file:mr-sm file:rounded-sm file:border-0 file:bg-surface-strong file:px-md file:py-xs file:text-sm file:font-medium disabled:opacity-50"
        />
      </label>
      <p id="upload-status" role="status" aria-live="polite" className="text-sm text-muted">
        {STATE_LABEL[state]}
      </p>
      {state === "rejected" || state === "error" ? (
        <Alert tone={state === "error" ? "warning" : "critical"} title={state === "error" ? "Could not upload" : "Upload not accepted"}>
          {message}
        </Alert>
      ) : null}
    </div>
  );
}
