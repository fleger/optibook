#! /bin/bash

# Script to optimize eBooks
# Supports ePubs and comic book archives (*.cbr, *.cbz)

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Requires the following dependencies:
#   - p7zip ≥ 9.38
#   - jpegtran from libjpeg, libjpeg-turbo or mozjpeg. Mozjpeg recommended to achieve best optimization ratio.
#   - optipng
#   - svgcleaner
#   - python
#   - python-html2text
#   - python-fonttools
#   - minify
#   - cwebp from libwebp
#   - waifu2x-ncnn-vulkan
#   - avifenc from libavif

# Optional dependencies:
#   - GNU parallel

OPTIBOOK_GIT_HASH='$Format:%H$'
OPTIBOOK_GIT_REFNAMES='$Format:%d$'
OPTIBOOK_GIT_DATE='$Format:%ci$'

AVIFENC_OPTS_DEFAULT='-s 4 -a tune=ssim -d 10'
CWEBP_OPTS_DEFAULT='-preset drawing -mt -m 6 -q 88 -sharp_yuv'
JPEGTRAN_OPTS_DEFAULT='-optimize -copy none'

: ${AVIFENC_OPTS:=$AVIFENC_OPTS_DEFAULT}
: ${CWEBP_OPTS:=$CWEBP_OPTS_DEFAULT}
: ${JPEGTRAN_OPTS:=$JPEGTRAN_OPTS_DEFAULT}

export AVIFENC_OPTS
export CWEBP_OPTS
export JPEGTRAN_OPTS

shopt -s globstar extglob nocaseglob
shopt -u failglob

optibook.status() {
    echo -ne "\r[$(basename "$1")] $2\033[K"
    echo "[$(basename "$1")] $2" >>"$OPTIBOOK_LOG"
}

optibook.size() {
    if [[ -d "$1" ]]; then
        du -sb "$1" | cut -f1
    else
        stat -L --printf="%s" "$1"
    fi
}

optibook.finalName() {
    local f="$1"
    local ext="$2"
    
    if [[ -d "$f" ]]; then
        f="$(dirname "$f")/$(basename "$f")"
        echo "FINAL NAME $f" >> "$OPTIBOOK_LOG"
    else
        f="${f%.*}"
    fi
    echo "$f.$ext"
}

optibook.optimize() {
    if [[ -s "$1" ]]; then
        local originalSize="$(optibook.size "$1")"
        local optimizedSize="$originalSize"
        
        local tmpdir="$(mktemp -d --tmpdir "optibook.XXXXXX")"
        
        # Uncompress file
        optibook.status "$1" "Decompressing archive"
        if optibook.decompress "$1" "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1; then
            optibook.status "$1" "Cleaning up unnecessary files"
            optibook.cleanUpGlobal "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
            optibook.status "$1" "Cleaning up unnecessary ePub files"
            optibook.cleanUpEpub "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
            optibook.status "$1" "Cleaning up comic book archive"
            optibook.cleanUpCB "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
            optibook.status "$1" "Optimizing HTML"
            optibook.optimizeHtml "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
            optibook.status "$1" "Optimizing CSS"
            optibook.optimizeCss "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
            optibook.status "$1" "Optimizing fonts"
            optibook.optimizeFonts "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
            if ! optibook.isEpub "$tmpdir" && [[ -n "$CONVERSION_FORMAT" ]]; then
                if [[ "$WAIFU2X_NOISE_LEVEL" != 0 ]]; then
                    optibook.status "$1" "Cleaning-up JPEGs"
                    optibook.cleanUpJpegs "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
                fi
                if [[ "$CONVERSION_FORMAT" == "webp" ]]; then
                    optibook.status "$1" "Converting images to WebP"
                    optibook.convertWebP "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
                elif [[ "$CONVERSION_FORMAT" == "avif" ]]; then
                    optibook.status "$1" "Converting images to AVIF"
                    optibook.convertAVIF "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
                fi
            fi
            optibook.status "$1" "Optimizing JPEGs"
            optibook.optimizeJpegs "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
            optibook.status "$1" "Optimizing PNGs"
            optibook.optimizePngs "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
            optibook.status "$1" "Optimizing SVGs"
            optibook.optimizeSvgs "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
            optibook.status "$1" "Recompressing archive"
            local tmpfile="$(mktemp -u --tmpdir "optibook.XXXXXX.zip")"
            if optibook.recompress "$tmpdir" "$tmpfile" >>"$OPTIBOOK_LOG" 2>&1; then
                optimizedSize="$(optibook.size "$tmpfile")"
                if [[ $optimizedSize -lt $originalSize ]] || [[ -d "$1" ]]; then
                    local extension
                    if optibook.isEpub "$tmpdir"; then
                        extension=epub
                    else
                        extension=cbz
                    fi
                    local outputName="$(optibook.finalName "$1" "$extension")"
                    mv -f "$tmpfile" "$outputName" >>"$OPTIBOOK_LOG" 2>&1
                    if [[ "$(realpath "$1")" != "$(realpath "$outputName")" ]]; then
                        rm -r "$1" >>"$OPTIBOOK_LOG" 2>&1
                    fi
                else
                    optimizedSize="$originalSize"
                    rm "$tmpfile" >>"$OPTIBOOK_LOG" 2>&1
                fi
            else
                optibook.status "$1" "Recompression failed" 1>&2
                rm "$tmpfile"
            fi
            rm -r "$tmpdir"
        else
           optibook.status "$1" "Decompression failed" 1>&2
        fi
        
        totalOriginalSize=$(( $totalOriginalSize + $originalSize ))
        totalOptimizedSize=$(( $totalOptimizedSize + $optimizedSize ))
        
        optibook.status "$1" "$(optibook.humanReadableBytes $originalSize) -> $(optibook.humanReadableBytes $optimizedSize): $(optibook.improvementRate $originalSize $optimizedSize)% ($(optibook.humanReadableBytes $(( $optimizedSize - $originalSize ))))"
        
        echo
    fi
}

optibook.isEpub() {
    [[ -f "$1/mimetype" ]]
}

optibook.recompress() {
    local -a compressorArgs=(-tzip -mx=9)
    if [[ -n "$OPTIBOOK_THREADS" ]]; then
        compressorArgs+=("-mmt$OPTIBOOK_THREADS")
    fi
    if optibook.isEpub "$1"; then
        # See https://sourceforge.net/p/sevenzip/feature-requests/1212/
        mv "$1/mimetype" "$1/!mimetype"
        7z a "${compressorArgs[@]}" "$2" "$1/!mimetype" "$1"/!(!mimetype)
        7z rn "$2" !mimetype mimetype
        mv "$1/!mimetype" "$1/mimetype"
    else
        7z a "${compressorArgs[@]}" "$2" "$1"/*
    fi
}

optibook.getMime() {
    file -L --mime-type --brief "$1"
}
export -f optibook.getMime

optibook.checkFileType() {
    local f="$1"
    shift
    if ! [[ -f "$f" ]]; then
        return 1
    fi
    local mime="$(optibook.getMime "$f")"
    echo "$f type is $mime"
    local candidate
    for candidate; do
        if [[ "$candidate" == "$mime" ]]; then
            return 0
        fi
    done
    return 2
}
export -f optibook.checkFileType

optibook.decompress() {
    if [[ -d "$1" ]]; then
        cp -r "$1"/* "$2"
    else
        7z x -o"$2" "$1"
    fi
}

optibook.hasParallel() {
    ! [[ -v "$OPTIBOOK_NO_PARALLEL" ]] && which parallel 2>&1 > /dev/null
}

optibook.parallel() {
    local -a parallelArgs=(--line-buffer)
    if [[ -n "$OPTIBOOK_THREADS" ]]; then
        parallelArgs+=("-j$OPTIBOOK_THREADS")
    fi
    parallel "${parallelArgs[@]}" "$@"
}

optibook.optijpg() {
    local f
    for f; do
        if optibook.checkFileType "$f" "image/jpeg" ; then
            jpegtran $JPEGTRAN_OPTS -outfile "$f" "$f"
        fi
    done
}
export -f optibook.optijpg

optibook.optimizeJpegs() {
    if optibook.hasParallel; then
        optibook.parallel optibook.optijpg {} ::: "$1"/**/*.{jpg,jpeg} || true
    else
        optibook.optijpg "$1"/**/*.{jpg,jpeg} || true
    fi
}


optibook.optipng() {
    local f
    for f; do
        if optibook.checkFileType "$f" "image/png" ; then
            optipng -strip all "$f" || true
        fi
    done
}
export -f optibook.optipng

optibook.optimizePngs() {
    if optibook.hasParallel; then
        optibook.parallel optibook.optipng {} ::: "$1"/**/*.png || true
    else
        optibook.optipng "$1"/**/*.png || true
    fi
}

optibook.convertWebP() {
    local f
    for f in "$1"/**/*.{png,tiff,tif,jpg,jpeg}; do
        if optibook.checkFileType "$f" "image/png" "image/tiff" "image/jpeg"; then
            local tmpfile="$(mktemp --tmpdir "optibook.XXXXXX.${f##*.}")"
            mv "$f" "$tmpfile"
            local dest="${f%.*}.webp"
            if cwebp $CWEBP_OPTS "$tmpfile" -o "$dest" && [[ $(optibook.size "$dest") -lt $(optibook.size "$tmpfile") ]]; then
                rm "$tmpfile"
            else
                if [[ -f "$dest" ]]; then
                    rm "$dest"
                fi
                mv -f "$tmpfile" "$f"
            fi
        fi
    done
}

optibook.convertAVIF() {
    local f
    for f in "$1"/**/*.{png,jpg,jpeg}; do
        if optibook.checkFileType "$f" "image/png" "image/jpeg"; then
            local tmpfile="$(mktemp --tmpdir "optibook.XXXXXX.${f##*.}")"
            mv "$f" "$tmpfile"
            local dest="${f%.*}.avif"
            if avifenc $AVIFENC_OPTS "$tmpfile" -o "$dest" && [[ $(optibook.size "$dest") -lt $(optibook.size "$tmpfile") ]]; then
                rm "$tmpfile"
            else
                if [[ -f "$dest" ]]; then
                    rm "$dest"
                fi
                mv -f "$tmpfile" "$f"
            fi
        fi
    done
}

optibook.cleanUpJpegs() {
    local f
    for f in "$1"/**/*.{jpg,jpeg}; do
        if optibook.checkFileType "$f" "image/jpeg"; then
            if waifu2x-ncnn-vulkan -s 1 -n "$WAIFU2X_NOISE_LEVEL" -i "$f" -o "${f%.*}.png"; then
                rm "$f"
            fi
        fi
    done
}

optibook.optimizeSvgs() {
    local h
    for h in "$1"/**/*.svg; do
        if optibook.checkFileType "$h" "image/svg+xml"; then
            svgcleaner "$h" "$h" || true
        fi
    done
}

optibook.optimizeHtml() {
    local h
    for h in "$1"/**/*.{html,xhtml,htm,xhtm,opf,ncx,xml}; do
        if optibook.checkFileType "$h" "text/html" "application/xhtml+xml" "text/xml"; then
            echo "Optimizing HTML file $h"
            local tmpfile="$(mktemp --tmpdir "optibook.XXXXXX.${h##*.}")"
            mv -f "$h" "$tmpfile"
            if minify --html-keep-document-tags --html-keep-end-tags --html-keep-quotes --html-keep-whitespace --xml-keep-whitespace --type "xml" "$tmpfile" -o "$h" && [[ -s "$h" ]]; then
                rm "$tmpfile"
            else
                mv -f "$tmpfile" "$h"
            fi
        fi
    done
}

optibook.cleanUpGlobal() {
    local d
    for d in "$1"/**/__MACOSX "$1"/**/.DS_Store "$1"/**/Thumbs.db "$1"/**/.directory "$1"/**/desktop.ini; do
        if [[ -d "$d" ]] || [[ -f "$d" ]]; then
            rm -r "$d"
        fi
    done
}

optibook.cleanUpEpub() {
    if optibook.isEpub "$1"; then
        if [[ -f "$1/iTunesMetadata.plist" ]]; then
            rm "$1/iTunesMetadata.plist"
        fi
        # TODO: remove Kobo style
    fi
}

optibook.cleanUpCB() {
    if ! optibook.isEpub "$1"; then
        rm "$1"/**/z* || true
    fi
}

optibook.optimizeFonts() {
    local sampleFile="$(mktemp)"
    local f
    for f in "$1"/**/*.ttf; do
        if optibook.checkFileType "$f" "font/ttf"; then
            if [[ ! -s "$sampleFile" ]]; then
                local h
                for h in "$1"/**/*.{html,xhtml,htm,xhtm}; do
                    if [[ -f "$h" ]]; then
                        html2text --no-wrap-links --ignore-emphasis --ignore-links --ignore-images --ignore-tables --single-line-break "$h" >> "$sampleFile"
                    fi
                done
            fi
            local tmpfile="$(mktemp --tmpdir "optibook.XXXXXX.${f##*.}")"
            mv -f "$f" "$tmpfile"
            if pyftsubset "$tmpfile" --text-file="$sampleFile" --output-file="$f" && [[ -s "$f" ]]; then
                rm "$tmpfile"
            else
                mv -f "$tmpfile" "$f"
            fi
        fi
    done
    rm "$sampleFile"
}

optibook.optimizeCss() {
    local h
    for h in "$1"/**/*.css; do
        if optibook.checkFileType "$h" "text/css" "text/plain"; then
            echo "Optimizing CSS file $h"
            local tmpfile="$(mktemp --tmpdir "optibook.XXXXXX.${h##*.}")"
            mv -f "$h" "$tmpfile"
            if minify --type css -o "$h" "$tmpfile" && [[ -s "$h" ]]; then
                rm "$tmpfile"
            else
                mv -f "$tmpfile" "$h"
            fi
        fi
    done
}

optibook.humanReadableBytes() {
    numfmt --to=iec-i --suffix="B" -- "$1"
}

optibook.usage() {
    echo "Optibook $OPTIBOOK_GIT_REFNAMES (commit $OPTIBOOK_GIT_HASH, $OPTIBOOK_GIT_DATE)"
    echo
    echo "Usage: $0 [-r (avif|webp)] [-n (0|1|2|3)] FILE1 [FILE2 ...]"
    echo
    echo "Reduces the size of Comic Book and ePub archives by optimizing the images, fonts, HTML and CSS data and by using a high level of compression."
    echo
    echo "Options:"
    echo "  -r (avif|webp)  Recompress images in Comic Book archives to further reduce size. May cause quality loss."
    echo "                  Not supported for ePub files."
    echo "  -n (0|1|2|3)    Remove JPEG artifacts using the Waifu2x algorithm before recompressing. Values 1, 2 and 3"
    echo "                  correspond respectively to a low, medium or high filtering strength. A value of 0 (default) will"
    echo "                  disable filtering. Requires using -r to have an effect."
    echo
    echo "Environment Variables:"
    echo
    echo "  OPTIBOOK_THREADS=n      Forces optibook to use n threads during the optimization and recompression steps."
    echo "  OPTIBOOK_NO_PARALLEL    If set prevent optibook from using GNU parallel during the optimization step."
    echo "  OPTIBOOK_LOG=file       Write logs to file."
    echo "  AVIFENC_OPTS            Options to pass to avifenc. Defaults: $AVIFENC_OPTS_DEFAULT"
    echo "  CWEBP_OPTS              Options to pass to cwebp. Defaults: $CWEBP_OPTS_DEFAULT"
    echo "  JPEGTRAN_OPTS           Options to pass to jpegtran. Defaults: $JPEGTRAN_OPTS_DEFAULT"
    echo
    exit 1
}

optibook.main() {
    : ${OPTIBOOK_LOG:=/dev/null}
    local totalOriginalSize=0
    local totalOptimizedSize=0

    local CONVERSION_FORMAT=""
    local WAIFU2X_NOISE_LEVEL=0

    while getopts "r:n:" option; do
        case "${option}" in
            r)
                if [[ "$OPTARG" != "avif" ]] && [[ "$OPTARG" != "webp" ]]; then
                    echo "-r: supported formats are avif, webp"
                    optibook.usage
                fi
                CONVERSION_FORMAT="$OPTARG"
                ;;
            n)
                WAIFU2X_NOISE_LEVEL="$OPTARG"
                if [[ $WAIFU2X_NOISE_LEVEL != 0 ]] && [[ $WAIFU2X_NOISE_LEVEL != 1 ]] && [[ $WAIFU2X_NOISE_LEVEL != 2 ]] && [[ $WAIFU2X_NOISE_LEVEL != 3 ]]; then
                    echo "-n: valid values are 0, 1, 2 or 3"
                    optibook.usage
                fi
                ;;
            *)
                optibook.usage
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ $# == 0 ]]; then
        optibook.usage
    fi

    export CONVERSION_FORMAT
    export WAIFU2X_NOISE_LEVEL

    local f
    for f; do
        optibook.optimize "$f"
    done

    echo "Total original size: $(optibook.humanReadableBytes $totalOriginalSize)"
    echo "Total optimized size: $(optibook.humanReadableBytes $totalOptimizedSize)"
    echo "Overall improvement: $(optibook.improvementRate $totalOriginalSize $totalOptimizedSize)% ($(optibook.humanReadableBytes $(( $totalOptimizedSize - 
$totalOriginalSize ))))"
}

optibook.improvementRate() {
    python -c "print('%0.2f' %(-100.0 * (1 - $2 / $1)))"
}

optibook.main "$@"
