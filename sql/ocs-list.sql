-- ocs-list.sql
-- Lists all non-archived opencode sessions globally as TSV.
-- Fields: id \t epoch_seconds \t path \t title \t content_blob
-- Date formatting (relative today, YYYY-MM-DD older) is done in awk.
-- Uses session.directory (actual cwd) not project.worktree (git root, often '/')
-- Used by: ocs fish function (piped to fzf for fuzzy search)

.headers off
.mode tabs
.nullvalue ''

SELECT s.id || char(9) ||
       CAST(s.time_updated/1000 AS TEXT) || char(9) ||
       s.directory || char(9) ||
       s.title || char(9) ||
       COALESCE((
         SELECT REPLACE(REPLACE(REPLACE(
           group_concat(json_extract(part.data, '$.text'), ' '),
           char(10), ' '), char(13), ' '), char(9), ' ')
         FROM part
         WHERE part.session_id = s.id
           AND json_extract(part.data, '$.type') = 'text'
           AND json_extract(part.data, '$.text') IS NOT NULL
           AND json_extract(part.data, '$.text') != ''
       ), '')
FROM session s
WHERE s.time_archived IS NULL
ORDER BY s.time_updated DESC;
