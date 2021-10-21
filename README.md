# optibook — An ePub and comic book archive optimizer

optibook is a Bash script that will try to optimize the size of ePub files (.epub) and comic book archives (.cbz, .cbr).

It combines several optimizations to help reduce the size of eBook files:
* Lossless optimization of JPEG, PNG and SVG images
* Minification of CSS and HTML files
* Embedded font optimization by subsetting the glyphs to the characters used in the eBook
* Better overall compression by taking advantage of 7-Zip more efficient Zip implementation to recompress the files
* Optional JPEG artifact reduction using the Waifu2x algorithm and lossy recompression of images from comic book archives to the more efficient WebP and AVIF formats

It can typically reduce the size of eBooks by up to 40% depending on the source.

## Usage

To losslessly optimize comic book archives or books:
```
./optibook.sh FILE1 [FILE2 ...]
```

To recompress comic book archives to WebP while applying while applying light denoising to reduce JPEG artifacts:
```
./optibook.sh -r webp -n 1 FILE1 [FILE2 ...]
```

Same thing using the AVIF file format:
```
./optibook.sh -r avif -n 1 FILE1 [FILE2 ...]
```

Complete syntax can be obtained by running optibook without argument.


## Required Dependencies

* [Bash](https://www.gnu.org/software/bash)
* [p7zip](http://p7zip.sourceforge.net) ≥ 9.38
* jpegtran from [mozjpeg](https://github.com/mozilla/mozjpeg) (recommended), [libjpeg-turbo](https://libjpeg-turbo.org/) or [libjpeg](https://www.ijg.org/)
* [OptiPNG](http://optipng.sourceforge.net)
* [svgcleaner](https://github.com/RazrFalcon/svgcleaner)
* [Python](https://www.python.org)
* [html2text](https://pypi.python.org/pypi/html2text)
* [fonttools](https://github.com/fonttools/fonttools)
* [minify](https://github.com/tdewolff/minify)
* cwebp from [libwebp](https://chromium.googlesource.com/webm/libwebp/)
* [waifu2x-ncnn-vulkan](https://github.com/nihui/waifu2x-ncnn-vulkan)
* avifenc from [libavif](https://github.com/AOMediaCodec/libavif)


## Optional Dependencies

* [GNU parallel](http://www.gnu.org/software/parallel/) to boost performance
