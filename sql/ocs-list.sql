-- ocs-list.sql
-- Lists all non-archived opencode sessions globally as TSV.
-- Fields: id \t epoch_seconds \t date_str \t path \t title \t content_blob
-- date_str is YYYY-MM-DD from SQLite strftime (avoids spawning `date -r` per row in awk).
-- Uses session.directory (actual cwd) not project.worktree (git root, often '/')
-- Used by: ocs fish function (piped to fzf for fuzzy search)
--
-- Performance: a partial expression index on part(session_id, json_extract(data,'$.text'))
-- WHERE type='text' makes the correlated subquery use the index instead of scanning
-- all part rows. See ocs.fish for the index creation step.

.headers off
.mode tabs
.nullvalue ''

SELECT s.id || char(9) ||
       CAST(s.time_updated/1000 AS TEXT) || char(9) ||
       strftime('%Y-%m-%d', s.time_updated/1000, 'unixepoch') || char(9) ||
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
