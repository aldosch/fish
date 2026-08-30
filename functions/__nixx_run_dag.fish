# __nixx_run_dag - parallel task runner with dependency graph and live display
#
# Runs multiple system-update tasks concurrently, respecting dependencies.
# Shows a live section-based display (one line per section) with spinners,
# live hints, and completion status. Populates $__nixx_results with
# "label|status|elapsed|logfile" entries for the nixx summary, and sets
# $__nixx_brew_upgraded_count from the brew-upgrade task's logfile.
#
# Task definition format (pipe-delimited; -m 6 keeps the command field intact
# even if it contains pipes, e.g. `curl ... | sh`):
#
#   "section|task_id|label|timeout|dep_ids|hint_pattern|command"
#
# Fields:
#   section       display group name (nix, brew, nvim, ...)
#   task_id       unique identifier for dependency references
#   label         human-readable task name (used in $__nixx_results)
#   timeout       max seconds before kill (watchdog sends TERM then KILL)
#   dep_ids       space-separated task IDs that must finish first (empty = none)
#   hint_pattern  literal string to grep from logfile for live progress (empty = none)
#   command       shell command to execute (may contain pipes, semicolons, etc.)
#
# Status codes: 0=pending 1=running 2=done 3=failed 4=blocked 5=timedout

function __nixx_run_dag
    _aldo_dracula_apply_palette

    if test (count $argv) -eq 0
        return 0
    end

    # --- parse task definitions into parallel arrays ---
    set -l t_section
    set -l t_id
    set -l t_label
    set -l t_timeout
    set -l t_deps
    set -l t_hint
    set -l t_cmd

    for def in $argv
        set -l p (string split -m 6 "|" -- $def)
        set -a t_section $p[1]
        set -a t_id      $p[2]
        set -a t_label   $p[3]
        set -a t_timeout $p[4]
        set -a t_deps    $p[5]
        set -a t_hint    $p[6]
        set -a t_cmd     $p[7]
    end

    set -l n_tasks (count $t_id)
    if test $n_tasks -eq 0
        return 0
    end

    # --- runtime state arrays ---
    set -l t_status
    set -l t_exitcode
    set -l t_logfile
    set -l t_exitfile
    set -l t_pid
    set -l t_watchdog
    set -l t_start
    set -l t_end
    set -l t_timedout

    for i in (seq $n_tasks)
        set -a t_status   0
        set -a t_exitcode ""
        set -a t_logfile  ""
        set -a t_exitfile ""
        set -a t_pid      0
        set -a t_watchdog 0
        set -a t_start    0
        set -a t_end      0
        set -a t_timedout 0
    end

    # --- build section list (unique, in first-appearance order) ---
    set -l sections
    for s in $t_section
        if not contains -- $s $sections
            set -a sections $s
        end
    end
    set -l n_sections (count $sections)

    # --- precompute colours via fish native set_color ---
    set -l c_reset (set_color normal)
    set -l c_purple (set_color $p_purple)
    set -l c_green  (set_color $p_green)
    set -l c_red    (set_color $p_red)
    set -l c_muted  (set_color $p_muted)
    set -l c_fg     (set_color $p_fg)

    # --- spinner frames ---
    set -l frames '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'
    set -l n_frames (count $frames)

    # --- hide cursor ---
    printf '\033[?25l'

    set -l frame_i 1
    set -l first_render 1

    # ============================ main scheduler loop ============================
    while true
        # 1. Check for completed tasks
        for i in (seq $n_tasks)
            if test $t_status[$i] -eq 1; and test -f "$t_exitfile[$i]"
                set t_exitcode[$i] (string trim (cat "$t_exitfile[$i]" 2>/dev/null))
                set t_end[$i] (date +%s)
                if test "$t_exitcode[$i]" = "0"
                    set t_status[$i] 2
                else if test "$t_exitcode[$i]" = "124"
                    set t_status[$i] 5
                    set t_timedout[$i] 1
                else
                    set t_status[$i] 3
                end
                if test $t_watchdog[$i] -gt 0
                    __nixx_kill_tree $t_watchdog[$i] KILL 2>/dev/null
                end
                rm -f "$t_exitfile[$i]"
            end
        end

        # 2. Launch ready tasks + propagate failures
        for i in (seq $n_tasks)
            if test $t_status[$i] -ne 0
                continue
            end

            # check dependencies (inline — Fish functions can't inherit locals)
            set -l deps_ready 1
            set -l dep_failed 0
            if test -n "$t_deps[$i]"
                for dep_id in (string split " " -- $t_deps[$i])
                    set -l dep_idx 0
                    for j in (seq $n_tasks)
                        if test "$t_id[$j]" = "$dep_id"
                            set dep_idx $j
                            break
                        end
                    end
                    if test $dep_idx -gt 0
                        switch $t_status[$dep_idx]
                            case 2
                                # satisfied
                            case 3 5 4
                                set dep_failed 1
                            case '*'
                                set deps_ready 0
                        end
                    end
                end
            end

            if test $dep_failed -eq 1
                set t_status[$i] 4
            else if test $deps_ready -eq 1
                # launch
                set -l logfile /tmp/nixx-dag-(string replace -ra '[^a-zA-Z0-9]' '-' $t_id[$i])-(date +%s).log
                set -l exitfile {$logfile}.exit
                set t_logfile[$i]  $logfile
                set t_exitfile[$i] $exitfile
                set t_start[$i]    (date +%s)

                fish -c "begin; $t_cmd[$i]; end >$logfile 2>&1; echo \$status >$exitfile" &
                set t_pid[$i] $last_pid

                # watchdog: kill after timeout, write 124 if the child didn't
                set -l to $t_timeout[$i]
                set -l jpid $t_pid[$i]
                fish -c "
                    sleep $to
                    if test -f $exitfile; exit 0; end
                    touch {$logfile}.timedout
                    __nixx_kill_tree $jpid TERM
                    sleep 2
                    __nixx_kill_tree $jpid KILL
                    test -f $exitfile; or echo 124 >$exitfile
                " &
                set t_watchdog[$i] $last_pid
                set t_status[$i] 1
            end
        end

        # 3. Render
        if test $first_render -eq 0
            printf '\033[%dA' $n_sections
        end

        for sec_idx in (seq $n_sections)
            set -l sec_name $sections[$sec_idx]

            # gather task indices in this section
            set -l sec_indices
            for i in (seq $n_tasks)
                if test "$t_section[$i]" = "$sec_name"
                    set -a sec_indices $i
                end
            end

            # compute section state
            set -l has_running 0
            set -l has_failed  0
            set -l has_pending 0
            set -l all_done    1
            set -l running_idx 0
            set -l first_start 0
            set -l last_end    0

            for i in $sec_indices
                if test $t_start[$i] -gt 0
                    if test $first_start -eq 0 -o "$t_start[$i]" -lt $first_start
                        set first_start $t_start[$i]
                    end
                end
                if test $t_end[$i] -gt 0
                    if test "$t_end[$i]" -gt $last_end
                        set last_end $t_end[$i]
                    end
                end
                switch $t_status[$i]
                    case 1
                        set has_running 1
                        set running_idx $i
                        set all_done 0
                    case 0
                        set has_pending 1
                        set all_done 0
                    case 3 5
                        set has_failed 1
                        set all_done 0
                    case 4
                        set all_done 0
                end
            end

            set -l line
            if test $has_running -eq 1
                set -l frame $frames[$frame_i]
                set -l hint ""
                if test -n "$t_hint[$running_idx]" -a -f "$t_logfile[$running_idx]"
                    set -l raw (grep -aF -- $t_hint[$running_idx] "$t_logfile[$running_idx]" 2>/dev/null | tail -1)
                    if test -n "$raw"
                        set raw (string replace -ra '\x1b\[[0-9;]*m' '' -- $raw | string trim)
                        if test -n "$raw"
                            set hint $raw
                        end
                    end
                end
                if test -n "$hint"
                    set line "$c_purple $frame$c_reset $c_fg$sec_name$c_reset$c_muted: $t_label[$running_idx]$c_reset$c_muted · $hint$c_reset"
                else
                    set line "$c_purple $frame$c_reset $c_fg$sec_name$c_reset$c_muted: $t_label[$running_idx]$c_reset"
                end
            else if test $has_failed -eq 1
                set -l elapsed (math "$last_end - $first_start")
                set -l et (__nixx_fmt_time $elapsed)
                set line "$c_red ✗$c_reset $c_fg$sec_name$c_reset$c_muted ($et)$c_reset"
            else if test $all_done -eq 1
                set -l elapsed (math "$last_end - $first_start")
                set -l et (__nixx_fmt_time $elapsed)
                set line "$c_green ✓$c_reset $c_fg$sec_name$c_reset$c_muted ($et)$c_reset"
            else if test $has_pending -eq 1
                set line "$c_muted – $sec_name$c_reset"
            else
                set line "$c_muted ⊘ $sec_name$c_reset"
            end

            printf '\r\033[K%s\n' $line
        end

        set first_render 0
        set frame_i (math "($frame_i % $n_frames) + 1")

        # 4. All done?
        set -l all_done 1
        for i in (seq $n_tasks)
            if test $t_status[$i] -eq 0 -o $t_status[$i] -eq 1
                set all_done 0
                break
            end
        end
        if test $all_done -eq 1
            break
        end

        sleep 0.1
    end

    # --- show cursor ---
    printf '\033[?25h'

    # --- populate $__nixx_results ---
    for i in (seq $n_tasks)
        set -l elapsed 0
        if test $t_start[$i] -gt 0 -a $t_end[$i] -gt 0
            set elapsed (math "$t_end[$i] - $t_start[$i]")
        end
        set -l et (__nixx_fmt_time $elapsed)
        set -l lf "$t_logfile[$i]"

        switch $t_status[$i]
            case 2
                set -g __nixx_results $__nixx_results "$t_label[$i]|ok|$et|$lf"
            case 3 5
                set -g __nixx_results $__nixx_results "$t_label[$i]|fail|$et|$lf"
            case 4
                set -g __nixx_results $__nixx_results "$t_label[$i]|blocked|0s|"
        end
    end

    # --- count brew upgrades from the brew-upgrade task's logfile ---
    for i in (seq $n_tasks)
        if test -n "$t_hint[$i]" -a "$t_hint[$i]" = "==> Upgrading " -a -f "$t_logfile[$i]"
            set -l count (grep -c '==> Upgrading ' "$t_logfile[$i]" 2>/dev/null)
            if test -n "$count"
                set -g __nixx_brew_upgraded_count (string trim $count)
            end
            break
        end
    end
end
