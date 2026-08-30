# yoink: download a website as LLM-ready markdown + binary assets
#
# Phase 1 — markdown content via crwl (crawl4ai)
# Phase 2 — binary assets via wget recursive spider
#
# Dependencies:
#   crwl   (crawl4ai CLI — `uv tool install crawl4ai`)
#   wget   (recursive asset download)
#   gum    (terminal UI — from nix/modules/apps.nix)
#   tree   (asset tree view — from nix/modules/apps.nix)
#
# Usage:
#   yoink [options] <url>
#
# Output:
#   <domain>/content/site.md   — full site as markdown (crwl)
#   <domain>/assets/**         — mirrored binary files (wget)

# ── helpers ──────────────────────────────────────────────────────────

# Safe grep -c: returns 0 on no match or missing file (never "0 0")
function _yoink_count_lines
    set -l pattern $argv[1]
    set -l file    $argv[2]
    if not test -s "$file"
        echo 0
        return
    end
    set -l n (grep -cF -- $pattern $file 2>/dev/null | string trim)
    if test -z "$n" -o "$n" = ""
        echo 0
    else
        echo $n
    end
end

function yoink
    _aldo_dracula_apply_palette

    argparse 'p/pages=' 'e/ext=' 'h/help' -- $argv
    or return 1

    if set -q _flag_help
        echo "usage: yoink [options] <url>"
        echo ""
        echo "options:"
        echo "  -p, --pages <N>     max pages for crwl crawl (default: 1000)"
        echo "  -e, --ext <list>    comma-separated asset extensions to download"
        echo "                      (default: pdf,docx,xlsx,pptx,doc,odt,ods,odp,"
        echo "                               zip,tar,gz,bz2,7z,rar,"
        echo "                               csv,json,yaml,yml,toml,xml,ndjson,"
        echo "                               md,rst,txt,org,"
        echo "                               png,jpg,jpeg,gif,webp,svg,ico,"
        echo "                               mp4,webm,mov,"
        echo "                               epub,mobi)"
        echo "  -h, --help          show this help"
        echo ""
        echo "output: ./<domain>/{content/site.md, assets/**}"
        return 0
    end

    # ── require url ──────────────────────────────────────────────────
    if test (count $argv) -ne 1
        gum log --level=error "expected exactly one URL"
        echo "usage: yoink [options] <url>"
        return 1
    end

    set url $argv[1]

    # ── dependency checks ────────────────────────────────────────────
    for dep in crwl wget gum tree
        if not command -q $dep
            gum log --level=error "dependency not found: $dep"
            switch $dep
                case crwl
                    echo "  install: uv tool install crawl4ai  (then add to uv/tools.txt)"
                case wget
                    echo "  install: add 'wget' to nix/modules/apps.nix → nixx l"
                case gum
                    echo "  install: add 'gum' to nix/modules/apps.nix → nixx l"
                case tree
                    echo "  install: add 'tree' to nix/modules/apps.nix → nixx l"
            end
            return 1
        end
    end

    # ── resolve options ──────────────────────────────────────────────
    set max_pages  (set -q _flag_pages; and echo $_flag_pages; or echo 1000)
    set extensions (set -q _flag_ext; and echo $_flag_ext; \
        or echo "pdf,docx,xlsx,pptx,doc,odt,ods,odp,zip,tar,gz,bz2,7z,rar,csv,json,yaml,yml,toml,xml,ndjson,md,rst,txt,org,png,jpg,jpeg,gif,webp,svg,ico,mp4,webm,mov,epub,mobi")

    # ── derive folder name from domain ───────────────────────────────
    set domain (string replace -r '^https?://' '' $url \
        | string replace -r '^www\.' '' \
        | string replace -r '[/:?#].*$' '')

    if test -z "$domain"
        gum log --level=error "could not parse domain from URL: $url"
        return 1
    end

    set outdir      "./$domain"
    set content_dir "$outdir/content"
    set assets_dir  "$outdir/assets"

    # ── detect re-run: snapshot existing assets ──────────────────────
    set is_rerun 0
    set prev_md_lines 0
    set snap_file (mktemp /tmp/yoink-snap-XXXXXX)

    if test -d "$outdir"
        set is_rerun 1
        if test -f "$content_dir/site.md"
            set prev_md_lines (wc -l < "$content_dir/site.md" | string trim)
        end
        # record mtime + path for every existing asset
        command find "$assets_dir" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort > $snap_file
    else
        touch $snap_file
    end

    # ── banner ───────────────────────────────────────────────────────
    echo ""
    gum style \
        --border=rounded \
        --border-foreground=$p_purple \
        --padding="0 2" \
        --bold \
        "  yoink  $url"
    echo ""

    if test $is_rerun -eq 1
        gum style --foreground=$p_orange --bold "  ↻  re-run — only changes will be highlighted"
        echo ""
    end

    gum style --foreground=$p_muted "  domain   $domain"
    gum style --foreground=$p_muted "  output   $outdir/"
    gum style --foreground=$p_muted "  pages    $max_pages"
    # wrap extensions into tidy groups rather than one overflowing line
    gum style --foreground=$p_muted "  assets   docs  · pdf docx xlsx pptx doc odt ods odp"
    gum style --foreground=$p_muted "           arch  · zip tar gz bz2 7z rar"
    gum style --foreground=$p_muted "           data  · csv json yaml yml toml xml ndjson"
    gum style --foreground=$p_muted "           text  · md rst txt org"
    gum style --foreground=$p_muted "           image · png jpg jpeg gif webp svg ico"
    gum style --foreground=$p_muted "           video · mp4 webm mov"
    gum style --foreground=$p_muted "           ebook · epub mobi"
    echo ""

    # ── create output dirs ───────────────────────────────────────────
    if not mkdir -p "$content_dir" "$assets_dir"
        gum log --level=error "could not create output directories"
        rm -f $snap_file
        return 1
    end

    # ════════════════════════════════════════════════════════════════
    # PHASE 1 — markdown content
    # ════════════════════════════════════════════════════════════════
    gum style --foreground=$p_purple --bold "▶ 1/2  content crawl"
    echo ""

    set crwl_log (mktemp /tmp/yoink-crwl-XXXXXX)

    gum spin \
        --spinner=points \
        --title="  crawling (max $max_pages pages)…" \
        --spinner.foreground=$p_purple \
        -- \
        fish -c "crwl crawl '$url' \
            --deep-crawl bfs \
            --max-pages $max_pages \
            -c 'mean_delay=1.0,semaphore_count=2' \
            -o md \
            -O '$content_dir/site.md' \
            > '$crwl_log' 2>&1"

    set crwl_status $status

    if test $crwl_status -ne 0
        gum log --level=warn "crwl exited $crwl_status — content may be incomplete"
        if test -s $crwl_log
            gum style --foreground=$p_red (cat $crwl_log | tail -5)
        end
    end

    if test -f "$content_dir/site.md"
        set new_lines (wc -l < "$content_dir/site.md" | string trim)
        set md_bytes  (command stat -f "%z" "$content_dir/site.md" 2>/dev/null)
        set md_kb     (math -s1 "$md_bytes / 1024")

        if test $is_rerun -eq 1
            set delta (math "$new_lines - $prev_md_lines")
            if test $delta -gt 0
                gum style --foreground=$p_green --bold \
                    "  ✓  site.md  $new_lines lines ($md_kb KB)   +"$delta" lines"
            else if test $delta -lt 0
                set abs_delta (math "0 - $delta")
                gum style --foreground=$p_orange --bold \
                    "  ✓  site.md  $new_lines lines ($md_kb KB)   -$abs_delta lines"
            else
                gum style --foreground=$p_muted \
                    "  ✓  site.md  $new_lines lines ($md_kb KB)   no change"
            end
        else
            gum style --foreground=$p_green --bold \
                "  ✓  site.md  $new_lines lines ($md_kb KB)"
        end
    end

    rm -f $crwl_log
    echo ""

    # ════════════════════════════════════════════════════════════════
    # PHASE 2 — binary assets
    # ════════════════════════════════════════════════════════════════
    gum style --foreground=$p_purple --bold "▶ 2/2  asset download"
    echo ""

    set wget_log (mktemp /tmp/yoink-wget-XXXXXX)

    # run wget in background; poll log for live progress display
    # reject-regex also strips:
    #   - WP image resize variants: filename-300x200.jpg, -1024x683.jpg, -scaled.jpg etc.
    #   - macOS .DS_Store files
    wget \
        --recursive \
        --level=5 \
        --timestamping \
        --no-parent \
        --accept=$extensions \
        --reject-regex='(\?|&|session|token|redirect|logout|login|-[0-9]+x[0-9]+\.(jpg|jpeg|png|gif|webp)|(-scaled|-rotated|-cropped)\.(jpg|jpeg|png|gif|webp)|\.DS_Store)' \
        --directory-prefix="$assets_dir" \
        --no-host-directories \
        --cut-dirs=0 \
        --user-agent="Mozilla/5.0 (compatible; sitedl/1.0)" \
        --wait=1 \
        --random-wait \
        --limit-rate=500k \
        -e robots=on \
        --verbose \
        "$url" > /dev/null 2> $wget_log &

    set wget_pid $last_pid
    set wget_start (date +%s)

    # braille spinner frames (1-indexed: Fish arrays start at 1)
    set spin_chars "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"
    set spin_i 1

    while kill -0 $wget_pid 2>/dev/null
        set frame $spin_chars[$spin_i]
        set spin_i (math "$spin_i % 10 + 1")

        # "saved [" matches lines like: 'path/file.pdf' saved [12345]
        # "not modified on server" matches timestamping skips
        set saved (_yoink_count_lines "saved \[" $wget_log)
        set skipped (_yoink_count_lines "not modified on server" $wget_log)
        set total_seen (math "$saved + $skipped")

        # current URL: lines starting with "--YYYY-MM-DD HH:MM:SS--  http"
        set cur_url (grep -E "^--[0-9]{4}-[0-9]{2}-[0-9]{2}" $wget_log 2>/dev/null \
            | tail -1 \
            | string replace -r '^--[0-9 :-]+--\s+' '' \
            | string trim)

        set elapsed (math (date +%s)" - $wget_start")
        set elapsed_fmt (math "$elapsed / 60")"m"(math "$elapsed % 60")"s"

        printf "\r  %s  %s saved  %s skipped   [%s]   %-50s" \
            $frame $saved $skipped $elapsed_fmt (string sub -l 50 $cur_url)

        sleep 0.2
    end

    wait $wget_pid
    set wget_status $status
    printf "\r%-100s\r" " "   # clear the progress line

    # ── robots.txt report ────────────────────────────────────────────
    set robots_count (_yoink_count_lines "robots.txt" $wget_log)
    if test "$robots_count" -gt 0 2>/dev/null
        echo ""
        gum style --foreground=$p_red --bold \
            "  ⚠  robots.txt blocked $robots_count path(s)"
        grep "robots.txt" $wget_log 2>/dev/null \
            | string replace -r '^.*Disallowed URL ' '' \
            | string replace -r '\s.*$' '' \
            | sort -u | head -10 \
            | while read -l blocked
                gum style --foreground=$p_muted "     $blocked"
            end
        echo ""

        if gum confirm \
            --affirmative="Retry ignoring robots.txt" \
            --negative="Keep as-is" \
            "  Retry without robots.txt restrictions?"

            echo ""
            gum style --foreground=$p_orange "  retrying — robots.txt ignored…"
            echo ""

            wget \
                --recursive \
                --level=5 \
                --timestamping \
                --no-parent \
                --accept=$extensions \
                --reject-regex='(\?|&|session|token|redirect|logout|login|-[0-9]+x[0-9]+\.(jpg|jpeg|png|gif|webp)|(-scaled|-rotated|-cropped)\.(jpg|jpeg|png|gif|webp)|\.DS_Store)' \
                --directory-prefix="$assets_dir" \
                --no-host-directories \
                --cut-dirs=0 \
                --user-agent="Mozilla/5.0 (compatible; sitedl/1.0)" \
                --wait=1 \
                --random-wait \
                --limit-rate=500k \
                -e robots=off \
                --verbose \
                "$url" > /dev/null 2>> $wget_log &

            set wget_pid $last_pid
            set wget_start (date +%s)
            set spin_i 1

            while kill -0 $wget_pid 2>/dev/null
                set frame $spin_chars[$spin_i]
                set spin_i (math "$spin_i % 10 + 1")
                set saved (_yoink_count_lines "saved \[" $wget_log)
                set skipped (_yoink_count_lines "not modified on server" $wget_log)
                set cur_url (grep -E "^--[0-9]{4}-[0-9]{2}-[0-9]{2}" $wget_log 2>/dev/null \
                    | tail -1 \
                    | string replace -r '^--[0-9 :-]+--\s+' '' \
                    | string trim)
                set elapsed (math (date +%s)" - $wget_start")
                set elapsed_fmt (math "$elapsed / 60")"m"(math "$elapsed % 60")"s"
                printf "\r  %s  %s saved  %s skipped   [%s]   %-50s" \
                    $frame $saved $skipped $elapsed_fmt (string sub -l 50 $cur_url)
                sleep 0.2
            end

            wait $wget_pid
            set wget_status $status
            printf "\r%-100s\r" " "
        end
    end

    if test $wget_status -ne 0 -a $wget_status -ne 8
        gum log --level=warn "wget exited $wget_status — some assets may be missing"
    end

    # ── diff assets: new / updated / unchanged ───────────────────────
    set new_snap (mktemp /tmp/yoink-snap2-XXXXXX)
    command find "$assets_dir" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort > $new_snap

    set count_new       0
    set count_updated   0
    set count_unchanged 0
    set new_files       ""
    set updated_files   ""

    while read -l entry
        # entry is: "<mtime> <path>"
        set parts   (string split -m 1 ' ' $entry)
        set mtime   $parts[1]
        set fpath   $parts[2]
        set relpath (string replace "$assets_dir/" "" $fpath)

        set old_entry (grep -F -- "$fpath" $snap_file 2>/dev/null | head -1)
        if test -z "$old_entry"
            set count_new (math "$count_new + 1")
            set new_files "$new_files\n    $relpath"
        else
            set old_mtime (string split -m 1 ' ' $old_entry)[1]
            if test "$mtime" != "$old_mtime"
                set count_updated (math "$count_updated + 1")
                set updated_files "$updated_files\n    $relpath"
            else
                set count_unchanged (math "$count_unchanged + 1")
            end
        end
    end < $new_snap

    rm -f $snap_file $new_snap $wget_log

    # ════════════════════════════════════════════════════════════════
    # SUMMARY
    # ════════════════════════════════════════════════════════════════
    echo ""
    gum style \
        --border=rounded \
        --border-foreground=$p_muted \
        --padding="0 2" \
        --bold \
        "  done  $outdir/"
    echo ""

    # content
    if test -f "$content_dir/site.md"
        set final_lines (wc -l < "$content_dir/site.md" | string trim)
        set final_bytes (command stat -f "%z" "$content_dir/site.md" 2>/dev/null)
        set final_kb    (math -s1 "$final_bytes / 1024")
        gum style --foreground=$p_cyan \
            "  content/site.md   $final_lines lines  ($final_kb KB)"
    end

    # asset change breakdown
    echo ""
    if test $is_rerun -eq 1
        if test $count_new -gt 0
            gum style --foreground=$p_green --bold "  + $count_new new"
            printf "$new_files\n" | while read -l f
                test -n "$f" && gum style --foreground=$p_green "  $f"
            end
        end
        if test $count_updated -gt 0
            gum style --foreground=$p_orange --bold "  ↻ $count_updated updated"
            printf "$updated_files\n" | while read -l f
                test -n "$f" && gum style --foreground=$p_orange "  $f"
            end
        end
        if test $count_unchanged -gt 0
            gum style --foreground=$p_muted "  · $count_unchanged unchanged"
        end
        if test $count_new -eq 0 -a $count_updated -eq 0 -a $count_unchanged -eq 0
            gum style --foreground=$p_muted "  · no assets found"
        end
    else
        set total_assets (math "$count_new + $count_updated + $count_unchanged")
        if test $total_assets -gt 0
            gum style --foreground=$p_green --bold "  + $total_assets asset(s) downloaded"
        else
            gum style --foreground=$p_muted "  · no assets found"
        end
    end

    # asset tree — prune empty dirs, filter WP resize variants & system junk
    # tree -I uses shell glob patterns (pipe-separated)
    set -l tree_ignore ".DS_Store|*-[0-9]*x[0-9]*.jpg|*-[0-9]*x[0-9]*.jpeg|*-[0-9]*x[0-9]*.png|*-[0-9]*x[0-9]*.gif|*-[0-9]*x[0-9]*.webp|*-scaled.*|*-rotated.*|*-cropped.*"
    set tree_count (command find "$assets_dir" -type f -not -name ".DS_Store" 2>/dev/null | count)
    if test $tree_count -gt 0
        echo ""
        gum style --foreground=$p_purple --bold "  assets"
        tree \
            -C \
            --prune \
            --noreport \
            --dirsfirst \
            -h \
            -I $tree_ignore \
            "$assets_dir" 2>/dev/null
    end

    echo ""
    functions -e _yoink_count_lines
end
