# Clinical Evaluation Sets

Empty in Sprint 0. Gold-standard question/expected-evidence pairs for the
confirmed clinical domain are authored in Sprint 1+ once the domain and
initial guideline set are approved (see MASTER_BACKLOG.md, epic E-25).

Expected structure per case (draft, subject to Clinical Safety Agent review):

```json
{
  "case_id": "uuid",
  "question": "string",
  "expected_scope_status": "within_scope | out_of_scope",
  "expected_document_ids": ["uuid"],
  "expected_pages": [12, 13],
  "expected_evidence_status": "sufficient | partial | insufficient | conflicting",
  "notes": "string"
}
```
