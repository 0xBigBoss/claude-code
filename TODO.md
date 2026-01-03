# TODO - Fix DuckDB Indexing Limit

## Completed
- [x] Identified issue: idx_messages_content index causes ART key size limit error (iteration 1)
- [x] Removed content index - ILIKE search works without it (iteration 1)
- [x] Deleted existing database and reindexed all sessions (iteration 1)
- [x] Verified all 4915 sessions indexed without errors (iteration 1)
- [x] Verified search command works (iteration 1)
- [x] Verified recent command works (iteration 1)

## In Progress
- None

## Pending
- None

## Blocked
- None

## Notes
- DuckDB's ART index has a 122KB key size limit
- Some message content exceeds this limit (e.g., 3.4MB messages)
- Solution: Remove the content column index since ILIKE search doesn't require it
- Alternative would be truncating content, but removing the unused index is cleaner
