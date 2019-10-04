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
#   - yuicompressor
#   - htmlcompressor
#   - cwebp from libwebp
#   - waifu2x-converter-cpp

# Optional dependencies:
#   - GNU parallel

shopt -s globstar extglob nocaseglob
shopt -u failglob

: ${WAIFU2X_NOISE_LEVEL:=1}

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
            if ! optibook.isEpub "$tmpdir"; then
                optibook.status "$1" "Cleaning-up JPEGs"
                optibook.cleanUpJpegs "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
                optibook.status "$1" "Converting images to WebP"
                optibook.convertLosslessWebP "$tmpdir" >>"$OPTIBOOK_LOG" 2>&1
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

optibook.checkFileType() {
    local f="$1"
    shift
    if ! [[ -f "$f" ]]; then
        return 1
    fi
    local mime="$(file -L --mime-type --brief "$f")"
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
            jpegtran -optimize -outfile "$f" -copy none "$f"
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

optibook.convertLosslessWebP() {
    local f
    for f in "$1"/**/*.{png,tiff,tif}; do
        if optibook.checkFileType "$f" "image/png" "image/tiff" ; then
            local tmpfile="$(mktemp --tmpdir "optibook.XXXXXX.${f##*.}")"
            mv "$f" "$tmpfile"
            local dest="${f%.*}.webp"
            if cwebp -preset drawing -mt -m 6 -q 88 -sharp_yuv  "$tmpfile" -o "$dest" && [[ $(optibook.size "$dest") -lt $(optibook.size "$tmpfile") ]]; then
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
	    if waifu2x-converter-cpp -m noise --noise-level "$WAIFU2X_NOISE_LEVEL" -i "$f" -o "${f%.*}.png"; then
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
    for h in "$1"/**/*.{html,xhtml,htm,xhtm}; do
        if  optibook.checkFileType "$h" "text/html" "application/xhtml+xml"; then
            local tmpfile="$(mktemp --tmpdir "optibook.XXXXXX.${h##*.}")"
            mv -f "$h" "$tmpfile"
            if htmlcompressor --preserve-line-breaks -o "$h" "$tmpfile" && [[ -s "$h" ]]; then
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
        if optibook.checkFileType "$h" "text/css"; then
            local tmpfile="$(mktemp --tmpdir "optibook.XXXXXX.${h##*.}")"
            mv -f "$h" "$tmpfile"
            if yuicompressor --type css -o "$h" "$tmpfile" && [[ -s "$h" ]]; then
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

optibook.main() {
    : ${OPTIBOOK_LOG:=/dev/null}
    local totalOriginalSize=0
    local totalOptimizedSize=0
    
    if [[ $# == 0 ]]; then
        echo "Usage: $0 FILE1 [FILE2 ...]"
        echo
        echo "Reduces the size of Comic Book and ePub archives by optimizing the images, fonts, HTML and CSS data and by using a high level of compression."
        echo
        echo "Environment Variables"
        echo
        echo "  OPTIBOOK_THREADS=n      Forces optibook to use n threads during the optimization and recompression steps."
        echo "  OPTIBOOK_NO_PARALLEL    If set prevent optibook from using GNU parallel during the optimization step."
        echo "  OPTIBOOK_LOG=file       Write logs to file."
        echo "  WAIFU2X_NOISE_LEVEL=n   Amount of noise reduction applied when reencoding JPEGs (1-3)."
        echo
        return 1
    fi

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
