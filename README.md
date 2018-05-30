# optibook — An ePub and comic book archive optimizer

optibook is a Bash script that will try to optimize the size of ePub files (.epub) and comic book archives (.cbz, .cbr).

It combines several optimizations to help reduce the size of eBook files:
* Lossless optimization of JPEG, PNG and SVG images
* Minification of CSS and HTML files
* Embedded font optimization by subsetting the glyphs to the characters used in the eBook
* Better overall compression by taking advantage of 7-Zip more efficient Zip implementation to recompress the files

It can typically reduce the size of eBooks by up to 40% depending on the source.

## Usage

```
./optibook.sh FILE1 [FILE2 ...]
```

## Dependencies

* [Bash](https://www.gnu.org/software/bash)
* [p7zip](http://p7zip.sourceforge.net) ≥ 9.38
* [jpgcrush](http://akuvian.org/src/jpgcrush.tar.gz)
* [ExifTool](https://sno.phy.queensu.ca/~phil/exiftool)
* [OptiPNG](http://optipng.sourceforge.net)
* [svgcleaner](https://github.com/RazrFalcon/svgcleaner)
* [Python](https://www.python.org)
* [html2text](https://pypi.python.org/pypi/html2text)
* [fonttools](https://github.com/fonttools/fonttools)
* [yuicompressor](https://yui.github.io/yuicompressor/)
* [htmlcompressor](https://code.google.com/archive/p/htmlcompressor/)
