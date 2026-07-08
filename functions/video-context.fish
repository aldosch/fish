# video-context: extract transcript + screenshots from a video for LLM context
#
# Dependencies:
#   brew install whisper-cpp ffmpeg   (ffmpeg is also managed via nix/modules/apps.nix)
#
# Whisper GGML models (not bundled with whisper-cpp, must be downloaded separately):
#   Default model dir: ~/.config/whisper-cpp/models/
#   Download a model, e.g.:
#     curl -L -o ~/.config/whisper-cpp/models/ggml-base.en.bin \
#       https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
#   Other models: tiny.en, base.en, small.en, medium.en, large-v3, large-v3-turbo
#   Full list: https://huggingface.co/ggerganov/whisper.cpp/tree/main

function video-context
    argparse \
        'm/model=' \
        'M/models-dir=' \
        'i/interval=' \
        'o/output=' \
        't/transcript-only' \
        'h/help' \
        -- $argv
    or return 1

    if set -q _flag_help
        echo "usage: video-context [options] <video-file>"
        echo ""
        echo "options:"
        echo "  -m, --model <name>       whisper model name (default: base.en)"
        echo "  -M, --models-dir <path>  directory containing ggml model files"
        echo "                           (default: ~/.config/whisper-cpp/models)"
        echo "  -i, --interval <secs>    screenshot interval in seconds"
        echo "                           (default: auto, ~20 frames for the video length)"
        echo "  -o, --output <dir>       output directory (default: <video>_context/)"
        echo "  -t, --transcript-only    skip screenshots"
        echo "  -h, --help               show this help"
        return 0
    end

    # --- input file ---
    if test (count $argv) -ne 1
        echo "error: expected exactly one video file argument"
        echo "usage: video-context [options] <video-file>"
        return 1
    end

    set input $argv[1]
    if not test -f "$input"
        echo "error: file not found: $input"
        # Check if the parent directory has video files — hints at a non-breaking space issue
        set input_dir (dirname -- "$input")
        if test -d "$input_dir"
            set candidates (command ls "$input_dir" 2>/dev/null | string match -r '\.(mov|mp4|mkv|m4v|avi|webm)$')
            if test (count $candidates) -gt 0
                echo ""
                echo "hint: the filename may contain non-breaking spaces (common in macOS screen recordings)."
                echo "try using a glob instead:"
                echo "  video-context (ls "(string escape -- "$input_dir")"/*.mov)"
            end
        end
        return 1
    end

    # --- dependency checks ---
    if not command -q ffmpeg
        echo "error: ffmpeg not found"
        echo "  install via nix: add 'ffmpeg' to nix/modules/apps.nix"
        return 1
    end

    if not command -q ffprobe
        echo "error: ffprobe not found (should come with ffmpeg)"
        return 1
    end

    if not command -q whisper-cli
        echo "error: whisper-cli not found"
        echo "  install: brew install whisper-cpp"
        echo "  or add 'whisper-cpp' to commonBrews in nix/modules/apps.nix and run: nixx l"
        return 1
    end

    # --- resolve model ---
    set model_name (set -q _flag_model; and echo $_flag_model; or echo "base.en")
    set models_dir (set -q _flag_models_dir; and echo $_flag_models_dir; or echo "$HOME/.config/whisper-cpp/models")
    set model_path "$models_dir/ggml-$model_name.bin"

    if not test -f "$model_path"
        set model_url "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$model_name.bin"
        echo "model not found: $model_path"
        echo ""
        printf "download ggml-%s.bin now? [y/N] " $model_name
        read -l answer
        if string match -qi 'y' -- $answer
            mkdir -p "$models_dir"
            echo "downloading $model_name..."
            curl -L --progress-bar -o "$model_path" "$model_url"
            if test $status -ne 0
                echo "error: download failed"
                rm -f "$model_path"
                return 1
            end
            echo "model saved to $model_path"
            echo ""
        else
            echo ""
            echo "to download manually:"
            echo "  curl -L -o \"$model_path\" \\"
            echo "    $model_url"
            echo ""
            echo "other available models: tiny.en, base.en, small.en, medium.en, large-v3, large-v3-turbo"
            return 1
        end
    end

    # --- resolve paths ---
    set dir (dirname -- "$input")
    set base (basename -- "$input")
    set name (string split -r -m1 . "$base")[1]

    if set -q _flag_output
        set outdir $_flag_output
    else
        set outdir "$dir/$name""_context"
    end

    # --- get video duration ---
    set duration (ffprobe -v error -show_entries format=duration -of csv=p=0 "$input" 2>/dev/null | string trim)
    if test -z "$duration"
        echo "error: could not read video duration from: $input"
        return 1
    end
    # round to integer
    set duration_int (math -s0 $duration)

    # --- compute screenshot interval ---
    if set -q _flag_interval
        set interval $_flag_interval
    else
        # target ~20 frames, clamped between 10s and 60s
        set interval (math -s0 "max(10, min(60, $duration_int / 20))")
    end

    set duration_fmt (math -s0 "$duration_int / 60"):(string pad -r -w2 -c0 (math -s0 "$duration_int % 60"))

    echo "video-context: $base ($duration_fmt)"
    echo "  model:    $model_name"
    echo "  output:   $outdir"
    if not set -q _flag_transcript_only
        set frame_count (math -s0 "$duration_int / $interval")
        echo "  interval: $interval""s (~$frame_count screenshots)"
    else
        echo "  mode:     transcript only"
    end
    echo ""

    # --- create output dir ---
    if not mkdir -p "$outdir"
        echo "error: could not create output directory: $outdir"
        return 1
    end

    # --- extract audio ---
    echo "[ 1/3 ] extracting audio..."
    set audio_path "$outdir/audio.wav"
    ffmpeg -hide_banner -loglevel error -y \
        -i "$input" \
        -ar 16000 -ac 1 -c:a pcm_s16le \
        "$audio_path"
    if test $status -ne 0
        echo "error: ffmpeg audio extraction failed"
        return 1
    end

    # --- transcribe ---
    echo "[ 2/3 ] transcribing with whisper ($model_name)..."
    set transcript_prefix "$outdir/transcript"
    whisper-cli \
        -m "$model_path" \
        -f "$audio_path" \
        -otxt -ovtt \
        -of "$transcript_prefix" \
        --no-timestamps false \
        2>/dev/null
    if test $status -ne 0
        echo "error: whisper-cli transcription failed"
        rm -f "$audio_path"
        return 1
    end

    rm -f "$audio_path"

    # --- screenshots ---
    if not set -q _flag_transcript_only
        echo "[ 3/3 ] capturing screenshots every $interval""s..."
        ffmpeg -hide_banner -loglevel error -y \
            -i "$input" \
            -vf "fps=1/$interval" \
            -q:v 3 \
            "$outdir/frame_%04d.jpg"
        if test $status -ne 0
            echo "error: ffmpeg screenshot extraction failed"
            return 1
        end
    else
        echo "[ 3/3 ] skipping screenshots (--transcript-only)"
    end

    # --- summary ---
    echo ""
    echo "done. output: $outdir/"
    echo ""
    for f in (ls "$outdir/")
        set size (command stat -f "%z" "$outdir/$f" 2>/dev/null; or command stat -c "%s" "$outdir/$f" 2>/dev/null)
        set size_kb (math -s1 "$size / 1024")
        printf "  %-30s %s KB\n" "$f" "$size_kb"
    end
end
