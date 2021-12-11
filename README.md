# compare-rms.pl

plot the peak and RMS values of two audio files and show the difference between them.
I used this to compare the results of my audio mastering plug-ins with others.

```
DESCRIPTION:
compare-rms plots the peak peak and RMS values
Usage: rms [OPTION...]
OPTIONS:
    -i --input <audio>      base path of any audio or video file to be plotted
                            the files to be compared have the names <audio>.1 and <audio>.2
    -o --output image       path of the target PNG file, if ommited use <audio>1.png and audio>2.png
    -r --resolution VALUE   RMS resolution for each line of output in seconds, default is 1.5
    -l --limit              cut off RMS values lower than limit in dB, default is -36
    -t --template FILE      use the given gnuplot template file instead of the build-in template
    -v --verbose            verbose output
    -h --help               this help
    --no-delete             do not delete temporary files

Example: compare bolero.1 (created with loudnorm plugin) and bolero.2 (created with ebur128_leveler_6s plugin):
$ compareRms.pl -i bolero
```

![](bolero.1.png)
![](bolero.2.png)
