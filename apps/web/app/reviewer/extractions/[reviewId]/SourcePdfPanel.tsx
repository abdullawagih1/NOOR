"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createExtractionReviewSourceAccessAction } from "@/lib/extraction-review/actions";

/**
 * Client Component: the only part of the review workspace that needs
 * browser-side JS. Mints its own short-lived signed URL (never persisted,
 * never logged — held only in this component's state) and re-mints it
 * shortly before expiry so a long review session doesn't hit a dead link.
 * Uses browser-native PDF rendering via <iframe> + the #page= URL
 * fragment convention rather than a bundled PDF.js viewer — see
 * docs/domain/extraction-review-lifecycle.md for the documented
 * limitation (page-jump support varies by browser).
 */
export function SourcePdfPanel({ extractionRunId, pageNumber }: { extractionRunId: string; pageNumber: number }) {
  const [signedUrl, setSignedUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const refreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const fetchSignedUrl = useCallback(async () => {
    try {
      const access = await createExtractionReviewSourceAccessAction(extractionRunId);
      setSignedUrl(access.signedUrl);
      setError(null);
      const msUntilExpiry = new Date(access.expiresAt).getTime() - Date.now();
      if (refreshTimer.current) clearTimeout(refreshTimer.current);
      refreshTimer.current = setTimeout(fetchSignedUrl, Math.max(msUntilExpiry - 30_000, 10_000));
    } catch {
      setError("Could not load the source document. It may have expired — try refreshing.");
    }
  }, [extractionRunId]);

  useEffect(() => {
    void fetchSignedUrl();
    return () => {
      if (refreshTimer.current) clearTimeout(refreshTimer.current);
    };
  }, [fetchSignedUrl]);

  if (error) {
    return (
      <div className="flex h-full items-center justify-center rounded-sm border border-border bg-surface p-md text-sm text-muted" role="alert">
        {error}
      </div>
    );
  }

  if (!signedUrl) {
    return (
      <div className="flex h-full items-center justify-center rounded-sm border border-border bg-surface p-md text-sm text-muted">
        Loading source document…
      </div>
    );
  }

  return (
    <iframe
      key={signedUrl}
      src={`${signedUrl}#page=${pageNumber}`}
      title="Original source PDF"
      className="h-full min-h-[480px] w-full rounded-sm border border-border"
    />
  );
}
