# Reviews Schema

Each security review result is recorded in a `reviews/` directory at the repository root as a JSON file with the following schema:

## Schema Version 1

### Structure
```json
{
  "version": 1,
  "source": "string",
  "source_url": "string (optional)",
  "reviewed_by": ["string"],
  "review_date": "ISO8601-UTC",
  "target_commit": "git-sha1 (optional)",
  "verdict": "approved" | "conditional" | "rejected",
  "risk_level": "low" | "medium" | "high" | "critical",
  "scan_findings": {
    "findings_count": "integer",
    "categories_flagged": ["string"]
  },
  "manual_review_summary": "string",
  "conditions_if_conditional": "string (optional)",
  "evidence_file_hash": "sha256 (optional - hash of full scan output)",
  "artifacts": {
    "scan_output": "filename (optional)",
    "detailed_notes": "filename (optional)"
  }
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | integer | ✓ | Schema version (currently 1) |
| `source` | string | ✓ | Name of code/skill/package reviewed |
| `source_url` | string | | URL to source repository or artifact |
| `reviewed_by` | array[string] | ✓ | Names/handles of reviewers using 5-persona framework |
| `review_date` | string | ✓ | ISO 8601 UTC timestamp of review completion |
| `target_commit` | string | | Git commit SHA-1 reviewed (if applicable) |
| `verdict` | enum | ✓ | Final decision: `approved`, `conditional` (approved with requirements), or `rejected` |
| `risk_level` | enum | ✓ | Overall risk: `low`, `medium`, `high`, `critical` |
| `scan_findings.findings_count` | integer | ✓ | Number of patterns flagged by scanner |
| `scan_findings.categories_flagged` | array[string] | ✓ | Scanner categories with findings |
| `manual_review_summary` | string | ✓ | Prose summary of 5-persona analysis and conclusions |
| `conditions_if_conditional` | string | | Required if verdict is `conditional`; describes approval constraints |
| `evidence_file_hash` | string | | SHA256 of full triage scan output for artifact integrity |
| `artifacts.scan_output` | string | | Filename of full JSON scan output (in same directory) |
| `artifacts.detailed_notes` | string | | Filename of detailed review notes (in same directory) |

## Usage

After performing a security review using the SKILL.md five-persona framework:

1. Run the scanner: `bash scripts/triage_scan.sh --json --output scan_<source>.json <target>`
2. Perform manual 5-persona adversarial read per SKILL.md
3. Record findings in `reviews/<source>_<date>.json` using this schema
4. Include links to scan output and detailed notes

## Example

See `examples/review-example.json` for a complete example record.
