#! /bin/bash

# Script to optimize eBooks
# Supports ePubs and comic book archives (*.cbr, *.cbz)

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# Requires the following dependencies:
#   - p7zip ≥ 9.38
#   - jpgcrush
#   - exiftool
#   - optipng
#   - python
#   - python-html2text
#   - python-fonttools
#   - yuicompressor
#   - htmlcompressor

shopt -s globstar extglob nocaseglob
shopt -u failglob

optibook.status() {
    echo -ne "\r[$(basename "$1")] $2\033[K"
}

optibook.size() {
    if [[ -d "$1" ]]; then
        du -sb "$1" | cut -f1
    else
        stat --printf="%s" "$1"
    fi
}

optibook.optimize() {
    if [[ -s "$1" ]]; then
        local originalSize="$(optibook.size "$1")"
        local optimizedSize="$originalSize"
        
        local tmpdir="$(mktemp -d --tmpdir "optibook.XXXXXX")"
        
        # Uncompress file
        optibook.status "$1" "Decompressing archive"
        if optibook.decompress "$1" "$tmpdir" >>"$details" 2>&1; then
            optibook.status "$1" "Cleaning up unnecessary files"
            optibook.cleanUpGlobal "$tmpdir" >>"$details" 2>&1
            optibook.status "$1" "Cleaning up unnecessary ePub files"
            optibook.cleanUpEpub "$tmpdir" >>"$details" 2>&1
            optibook.status "$1" "Cleaning up comic book archive"
            optibook.cleanUpCB "$tmpdir" >>"$details" 2>&1
            optibook.status "$1" "Optimizing HTML"
            optibook.optimizeHtml "$tmpdir" >>"$details" 2>&1
            optibook.status "$1" "Optimizing CSS"
            optibook.optimizeCss "$tmpdir" >>"$details" 2>&1
            optibook.status "$1" "Optimizing fonts"
            optibook.optimizeFonts "$tmpdir" >>"$details" 2>&1
            optibook.status "$1" "Optimizing JPEGs"
            optibook.optimizeJpegs "$tmpdir" >>"$details" 2>&1
            optibook.status "$1" "Optimizing PNGs"
            optibook.optimizePngs "$tmpdir" >>"$details" 2>&1
            optibook.status "$1" "Recompressing archive"
            local tmpfile="$(mktemp -u --tmpdir "optibook.XXXXXX.zip")"
            if optibook.recompress "$tmpdir" "$tmpfile" >>"$details" 2>&1; then
                optimizedSize="$(optibook.size "$tmpfile")"
                if [[ $optimizedSize -lt $originalSize ]]; then
                    rm -r "$1" >>"$details" 2>&1
                    local extension
                    if optibook.isEpub "$tmpdir"; then
                        extension=epub
                    else
                        extension=cbz
                    fi
                    mv "$tmpfile" "${1%.*}.$extension" >>"$details" 2>&1
                else
                    optimizedSize="$originalSize"
                    rm "$tmpfile" >>"$details" 2>&1
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
        
        optibook.status "$1" "$(optibook.humanReadableBytes $originalSize) -> $(optibook.humanReadableBytes $optimizedSize): $(optibook.improvementRate $originalSize $optimizedSize)% (-$(optibook.humanReadableBytes $(( $originalSize - $optimizedSize  ))))"
        
        echo
    fi
}

optibook.isEpub() {
    [[ -f "$1/mimetype" ]]
}

optibook.recompress() {
    if optibook.isEpub "$1"; then
        # See https://sourceforge.net/p/sevenzip/feature-requests/1212/
        mv "$1/mimetype" "$1/!mimetype"
        7z a -tzip -mx=9 "$2" "$1/!mimetype" "$1"/!(!mimetype)
        7z rn "$2" !mimetype mimetype
        mv "$1/!mimetype" "$1/mimetype"
    else
        7z a -tzip -mx=9 "$2" "$1"/*
    fi
    
}

optibook.decompress() {
    if [[ -d "$1" ]]; then
        cp -r "$1"/* "$2"
    else
        7z x -o"$2" "$1"
    fi
}

optibook.optimizeJpegs() {
    # Workaround issue where jpgcrush does not work
    # when JPEGs are on a separate filesystem as PWD.
    pushd "$1"
    jpgcrush **/*.@(jpg|jpeg) || true
    popd
    exiftool -All= -overwrite_original "$1"/**/*.@(jpg|jpeg) || return @
}

optibook.optimizePngs() {
    optipng "$1"/**/*.png || true
}

optibook.optimizeHtml() {
    local h
    for h in  "$1"/**/*.@(html|xhtml|htm|xhtm); do
        if [[ -f "$h" ]]; then
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
    for d in "$1"/**/__MACOSX "$1"/**/.DS_Store "$1"/**/Thumbs.db "$1"/**/.directory; do
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
    for f in  "$1"/**/*.ttf; do
        if [[ -f "$f" ]]; then
            if [[ ! -s "$sampleFile" ]]; then
                local h
                for h in "$1"/**/*.@(html|xhtml|htm|xhtm); do
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
    for h in  "$1"/**/*.css; do
        if [[ -f "$h" ]]; then
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
    numfmt --to=iec-i --suffix="B" "$1"
}

optibook.main() {
    local details=/dev/null
    local totalOriginalSize=0
    local totalOptimizedSize=0
    
    if [[ $# == 0 ]]; then
        echo "Usage: $0 FILE1 [FILE2 ...]"
        echo
        echo "Reduce the size of Comic Book and ePub archives by optimizing the images, fonts, HTML and CSS data and by using a high level of compression."
        return 1
    fi

    local f
    for f; do
        optibook.optimize "$f"
    done
        
    echo "Total original size: $(optibook.humanReadableBytes $totalOriginalSize)"
    echo "Total optimized size: $(optibook.humanReadableBytes $totalOptimizedSize)"
    echo "Overall improvement: $(optibook.improvementRate $totalOriginalSize $totalOptimizedSize)% (-$(optibook.humanReadableBytes $(( $totalOriginalSize - $totalOptimizedSize ))))"
}

optibook.improvementRate() {
    python -c "print('%0.2f' %(-100.0 * (1 - $2 / $1)))"
}

optibook.main "$@"
