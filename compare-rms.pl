#!/usr/bin/perl
use warnings;
use strict;

#use Data::Dumper;
use File::Basename;
use Getopt::Long;
use Data::Dumper;
my $tempDir = '/tmp';

my $minRms     = -50;
my $resolution = 3;
my $size       = '1000,1000';
my $template   = undef;
my $help       = undef;
my $verbose    = undef;
my $pngFile    = undef;
my $noDelete   = undef;
my $audioFile  = undef;

sub execute {
	my $command = shift;
	print STDERR "execute: $command\n";
	print STDERR `$command 2>&1`;
	my $exitCode = $? >> 8;
	error("$command died with error $exitCode: $!") if $exitCode != 0;
}

Getopt::Long::GetOptions(
	"i|input=s"      => \$audioFile,
	"o|output=s"     => \$pngFile,
	"r|resolution=s" => \$resolution,
	"t|template=s"   => \$template,
	"l|limit=i"      => \$minRms,
	"h|help"         => \$help,
	"v|verbose"      => \$verbose,
	"no-delete"      => \$noDelete,
) or error("Error in command line arguments\n");

if ($help) {
	usage();
	exit();
}
error("missing parameter --input for audio file") unless defined $audioFile;
error("audio file '$audioFile.1' does not exist") unless -e $audioFile . '.1';
error("template file '$template' does not exist") if ( defined $template ) && ( !-e $template );
error("invalid resolution '$resolution'") if $resolution <= 0;

# use the positive value internally
$minRms *= -1 if $minRms < 0;
my $data = {};

my $dataFile1 = $tempDir . '/' . basename($audioFile) . '-plot1.data';
my $rmsFile1  = $tempDir . '/' . basename($audioFile) . '-plot1.rms';
getData( $audioFile . '.1', $rmsFile1 );
buildDataFile( $data, $rmsFile1, $dataFile1, 0 );

my $dataFile2 = $tempDir . '/' . basename($audioFile) . '-plot2.data';
my $rmsFile2  = $tempDir . '/' . basename($audioFile) . '-plot2.rms';
getData( $audioFile . '.2', $rmsFile2 );
buildDataFile( $data, $rmsFile2, $dataFile2, 0 );

my $dataFile3 = $tempDir . '/' . basename($audioFile) . '-plot3.data';
my $rmsFile3  = $tempDir . '/' . basename($audioFile) . '-plot3.rms';
getData( $audioFile . '.3', $rmsFile3 );
buildDataFile( $data, $rmsFile3, $dataFile3, 0 );

my $dataFileMerge = $tempDir . '/' . basename($audioFile) . '-plot-merge.data';
my $lastDate = mergeDataFiles( $data, [ $dataFile1, $dataFile2, $dataFile3 ], $dataFileMerge );

my $plotFile = $tempDir . '/' . basename($audioFile) . '.plot';
$pngFile = dirname($audioFile) . '/' . basename($audioFile) . '.1.png';
plot( $plotFile, $dataFile1, $dataFile2, $dataFile3, $dataFileMerge, $lastDate );

$pngFile = dirname($audioFile) . '/' . basename($audioFile) . '.2.png';
plot2( $plotFile, $dataFile1, $dataFile2, $dataFile3, $dataFileMerge, $lastDate );

compareRms($dataFileMerge);

sub getData {
	my $audioFile = shift;
	my $rmsFile   = shift;

	unlink $rmsFile if -e $rmsFile;
	my $verboseParam = '';
	$verboseParam = " -v" if defined $verbose;

	my $command = "nice rms -r '$resolution' -i '$audioFile' -o '$rmsFile' $verboseParam";
	print STDERR "execute $command\n";
	print STDERR `$command 2>&1`;
	my $exitCode = $? >> 8;
	error("rms died with error $exitCode: $!") if $exitCode != 0;
}

sub buildDataFile {
	my $data     = shift;
	my $rmsFile  = shift;
	my $dataFile = shift;
	my $offset   = shift;

	$offset = 0 unless defined $offset;

	unlink $dataFile if -e $dataFile;

	open my $file, "<", $rmsFile;
	open my $out,  ">", $dataFile;

	while (<$file>) {
		my $line = $_;
		my @vals = split( /\s+/, $line );
		if ( $line =~ /^#/ ) {
			print $out $line;
			next;
		}
		next unless @vals == 5;
		my $date = $vals[0] + $offset;
		$date = $resolution * int( $date / $resolution + 0.5 );
		$date = sprintf( "%.01f", $date );
		for my $i ( 1 .. scalar(@vals) - 1 ) {
			my $val = $vals[$i];

			if ( $i == 1 ) {
				$data->{$date}->{$dataFile}->{rmsL} = $val;
			}
			if ( $i == 2 ) {
				$data->{$date}->{$dataFile}->{rmsR} = $val;
			}

			# silence detection
			if ( $val < -200 ) {
				$vals[$i] = '-';
				next;
			}

			# cut off signal lower than minRMS
			$val = -$minRms if $val < -$minRms;

			# get absolute value
			$val = abs($val);

			# inverse value for plot (60db-val= plotVal)
			$val = $minRms - $val;
			$vals[$i] = $val;
		}
		print $out join( " ", @vals ) . "\n";
	}
	close $file;
	close $out;
}

sub compareRms {
	my $dataFileMerge = shift;

	my $sum1    = 0;
	my $sum2    = 0;
	my $sum3    = 0;
	my $n       = 0;
    my $noise   = -50;

    my ($oldTime, $oldL1, $oldR1, $oldL2, $oldR2, $oldL3, $oldR3 );

	open my $file, "<", $dataFileMerge;

	while (<$file>) {
		my $line = $_;
        print $line;

		chomp $line;
		my ( $time, $l1, $r1, $l2, $r2, $l3, $r3 ) = split( /\s+/, $line );

        if ($n==0){
            $oldTime = $time;
            $oldL1 = $l1;
            $oldL2 = $l2;
            $oldL3 = $l3;

            $oldR1 = $r1;
            $oldR2 = $r2;
            $oldR3 = $r3;
        }

		my $dtime = $time - $oldTime;
		$dtime = 0.1 if $dtime == 0;

        my $dl1 = abs( $l1 - $oldL1);
        my $dl2 = abs( $l2 - $oldL2);
        my $dl3 = abs( $l3 - $oldL3);

        my $dr1 = abs( $r1 - $oldR1);
        my $dr2 = abs( $r2 - $oldR2);
        my $dr3 = abs( $r3 - $oldR3);

		$sum1 += abs( ( $dl1 - $dl2 ) / $dtime ) if ($l1>$noise) || ($l2>$noise);
		$sum1 += abs( ( $dr1 - $dr2 ) / $dtime ) if ($r1>$noise) || ($r2>$noise);

		$sum2 += abs( ( $dl1 - $dl3 ) / $dtime ) if ($l1>$noise) || ($l3>$noise);
		$sum2 += abs( ( $dr1 - $dr3 ) / $dtime ) if ($r1>$noise) || ($r3>$noise);

		$sum3 += abs( ( $dl2 - $dl3 ) / $dtime ) if ($l2>$noise) || ($l3>$noise);
		$sum3 += abs( ( $dr2 - $dr3 ) / $dtime ) if ($r2>$noise) || ($r3>$noise);

		$n += $dtime;
		$oldTime = $time;

        $oldL1 = $l1;
        $oldL2 = $l2;
        $oldL3 = $l3;

        $oldR1 = $r1;
        $oldR2 = $r2;
        $oldR3 = $r3;

	}
	close $file;

	#$sum1 *= 1000;
	#$sum2 *= 1000;
	#$sum3 *= 1000;


	#$sum1 /= $n if $n != 0;
	#$sum2 /= $n if $n != 0;
	#$sum3 /= $n if $n != 0;

	printf ("SUM A-B: %.03f\n" , $sum1);
	printf ("SUM A-C: %.03f\n" , $sum2);
    printf ("DELTA: %.03f\n" , abs($sum1 - $sum2));
}

sub mergeDataFiles {
	my $data          = shift;
	my $dataFiles     = shift;
	my $dataFileMerge = shift;

	my $out          = '';
	my $lastL        = {};
	my $lastR        = {};
	my $lastDate     = '';
	my $previousTime = 0;
	for my $time ( sort { $a <=> $b } ( keys %$data ) ) {
		my $cols = $data->{$time};
		$out .= $time;

		for my $filename (@$dataFiles) {

			my $l = $cols->{$filename}->{rmsL};
			unless ( defined $l ) {
				$l = $lastL->{$filename};
			} else {
				$lastL->{$filename} = $l;
			}

			my $r = $cols->{$filename}->{rmsR};
			unless ( defined $r ) {
				$r = $lastR->{$filename};
			} else {
				$lastR->{$filename} = $r;
			}

			$out .= " $l $r";
		}
		$out .= "\n";
		$previousTime = $time;
		$lastDate     = $time;
	}

	open my $file, '>', $dataFileMerge;
	print $file $out;
	close $file;

	return $lastDate;
}

sub plot {
	my $plotFile      = shift;
	my $dataFile1     = shift;
	my $dataFile2     = shift;
	my $dataFile3     = shift;
	my $dataFileMerge = shift;
	my $lastDate      = shift;

	unlink $plotFile if -e $plotFile;
	unlink $pngFile  if -e $pngFile;

	unless ( defined $template ) {
		my @ytics = ();
		for ( my $i = -$minRms ; $i <= $minRms ; $i += 6 ) {
			push @ytics, '"-' . ( $minRms - abs($i) ) . ' dB" ' . ($i);
		}
		my $ytics    = join( ", ", @ytics );
		my $ps       = ' w l';
		my $lmargin1 = 8;
		my $lmargin2 = 8;
		my $yrange2  = '-16:16';
		my $ytics2   = '-16,4';

		my $plot = qq{
            set terminal png background rgb 'black' truecolor nocrop enhanced size $size font "Droid Sans,8"
            set output "$pngFile";
     		set multiplot layout 6,1
            set border lc rgb '#f0f0f0f0'
            set style fill transparent solid 0.3
            set style data lines
            #set style function filledcurves y1=0
            set nokey
            set grid

            #set xdata time
            #set timefmt "%s"
            #set format x "%H:%M:%S"
            set xrange[0:$lastDate]

            set ytics ($ytics)
            set yrange [-$minRms:$minRms]
            set lmargin $lmargin1

            plot \\
            '$dataFile1' using 1:( (\$4)) lc rgb "#50ee9999" w filledcurves y1=0 title "maxL",\\
            '$dataFile1' using 1:(-(\$5)) lc rgb "#5099ee99" w filledcurves y1=0 title "maxR",\\
            '$dataFile1' using 1:( (\$2)) lc rgb "#50ff0000" w filledcurves y1=0 title "rmsL",\\
            '$dataFile1' using 1:(-(\$3)) lc rgb "#5000ff00" w filledcurves y1=0 title "rmsR"\\
            ;

		    MAX=GPVAL_X_MAX
		    MIN=GPVAL_X_MIN
		    #set xrange [0:MAX+(MAX-MIN)*0.05]

            set yrange [$yrange2]
            set ytics $ytics2
            set lmargin $lmargin2
            plot \\
            '$dataFileMerge' using 1:(-(\$2-\$4)) lc rgb "#50ee9999" $ps title "maxL",\\
            '$dataFileMerge' using 1:(-(\$3-\$5)) lc rgb "#5099ee99" $ps title "maxR"\\
            ;

            set ytics ($ytics)
            set yrange [-$minRms:$minRms]
            set lmargin $lmargin1
            plot \\
            '$dataFile2' using 1:( (\$4)) lc rgb "#50ee9999" w filledcurves y1=0 title "maxL",\\
            '$dataFile2' using 1:(-(\$5)) lc rgb "#5099ee99" w filledcurves y1=0 title "maxR",\\
            '$dataFile2' using 1:( (\$2)) lc rgb "#50ff0000" w filledcurves y1=0 title "rmsL",\\
            '$dataFile2' using 1:(-(\$3)) lc rgb "#5000ff00" w filledcurves y1=0 title "rmsR"\\
            ;

            set yrange [$yrange2]
            set ytics $ytics2
            set lmargin $lmargin2
            plot \\
            '$dataFileMerge' using 1:(-(\$2-\$6)) lc rgb "#50ee9999" $ps title "maxL",\\
            '$dataFileMerge' using 1:(-(\$3-\$7)) lc rgb "#5099ee99" $ps title "maxR"\\
            ;

            set ytics ($ytics)
            set yrange [-$minRms:$minRms]
            set lmargin $lmargin1
            plot \\
            '$dataFile3' using 1:( (\$4)) lc rgb "#50ee9999" w filledcurves y1=0 title "maxL",\\
            '$dataFile3' using 1:(-(\$5)) lc rgb "#5099ee99" w filledcurves y1=0 title "maxR",\\
            '$dataFile3' using 1:( (\$2)) lc rgb "#50ff0000" w filledcurves y1=0 title "rmsL",\\
            '$dataFile3' using 1:(-(\$3)) lc rgb "#5000ff00" w filledcurves y1=0 title "rmsR"\\
            ;

            set yrange [$yrange2]
            set ytics $ytics2
            set lmargin $lmargin2
            plot \\
            '$dataFileMerge' using 1:(-(\$4-\$6)) lc rgb "#50ee9999" $ps title "maxL",\\
            '$dataFileMerge' using 1:(-(\$5-\$7)) lc rgb "#5099ee99" $ps title "maxR"\\
            ;

        };

		open my $file, ">", $plotFile || die("cannot write plot file $plotFile");
		print $file $plot;
		close $file;
	}

	my $command = "gnuplot '$plotFile'";
	$command = "gnuplot '$template'" if defined $template;

	execute($command);
	print STDERR "rmsPlot='$pngFile'\n";
}

# plot deltas only
sub plot2 {
	my $plotFile      = shift;
	my $dataFile1     = shift;
	my $dataFile2     = shift;
	my $dataFile3     = shift;
	my $dataFileMerge = shift;
	my $lastDate      = shift;

	print "dataFile $dataFileMerge\n";

	unlink $plotFile if -e $plotFile;
	unlink $pngFile  if -e $pngFile;

	unless ( defined $template ) {
		my @ytics = ();
		for ( my $i = -$minRms ; $i <= $minRms ; $i += 6 ) {
			push @ytics, '"-' . ( $minRms - abs($i) ) . ' dB" ' . ($i);
		}
		my $ytics    = join( ", ", @ytics );
		my $ps       = ' w l';
		my $lmargin1 = 8;
		my $lmargin2 = 8;
		my $yrange2  = '-16:16';
		my $ytics2   = '-16,4';

		my $plot = qq{
            set terminal png background rgb 'black' truecolor nocrop enhanced size $size font "Droid Sans,8"
            set output "$pngFile";
     		set multiplot layout 3,1
            set border lc rgb '#f0f0f0f0'
            set style fill transparent solid 0.3
            set style data lines
            #set style function filledcurves y1=0
            set nokey
            set grid

            #set xdata time
            #set timefmt "%s"
            #set format x "%H:%M:%S"
            #set xrange[0:$lastDate]

            set yrange [$yrange2]
            set ytics $ytics2
            set lmargin $lmargin2
            plot \\
            '$dataFileMerge' using 1:(-(\$2-\$4)) lc rgb "#50ee9999" $ps title "maxL",\\
            '$dataFileMerge' using 1:(-(\$3-\$5)) lc rgb "#5099ee99" $ps title "maxR"\\
            ;

		    MAX=GPVAL_X_MAX
		    MIN=GPVAL_X_MIN
		    #set xrange [0:MAX+(MAX-MIN)*0.05]

            set yrange [$yrange2]
            set ytics $ytics2
            set lmargin $lmargin2
            plot \\
            '$dataFileMerge' using 1:(-(\$2-\$6)) lc rgb "#50ee9999" $ps title "maxL",\\
            '$dataFileMerge' using 1:(-(\$3-\$7)) lc rgb "#5099ee99" $ps title "maxR"\\
            ;

            set yrange [$yrange2]
            set ytics $ytics2
            set lmargin $lmargin2
            plot \\
            '$dataFileMerge' using 1:(-(\$4-\$6)) lc rgb "#50ee9999" $ps title "maxL",\\
            '$dataFileMerge' using 1:(-(\$5-\$7)) lc rgb "#5099ee99" $ps title "maxR"\\
            ;

        };

		open my $file, ">", $plotFile || die("cannot write plot file $plotFile");
		print $file $plot;
		close $file;
	}

	my $command = "gnuplot '$plotFile'";
	$command = "gnuplot '$template'" if defined $template;

	execute($command);
	print STDERR "rmsPlot='$pngFile'\n";
}

sub usage {
	print STDERR q{
plot RMS values from audio file

DESCRIPTION:
compareRms will parse audio input and calculate RMS values for a given duration.
The results are plotted to an PNG image.

Usage: compareRms [OPTION...] <audio>

OPTIONS:
    -i --input  <audio>     path of any audio or video file to be plotted
    -o --output <image>     path of target PNG file, if ommited use <audio>.png
    -r --resolution <value> RMS resolution for each line of output in seconds, default is 1.5
    -l --limit              cut off RMS values lower than limit in dB, default is -36
    -t --template <file>    use given gnuplot template file instead of build-in template
    -v --verbose            verbose output
    -h --help               this help
    --no-delete             do not delete files
}
}

sub error {
	print "ERROR: " . $_[0] . "\n";
	exit 1;
}

END {
	return if defined $noDelete;
	unlink $dataFile1 if ( defined $dataFile1 ) && ( -e $dataFile1 );
	unlink $rmsFile1  if ( defined $rmsFile1 )  && ( -e $rmsFile1 );
	unlink $dataFile2 if ( defined $dataFile2 ) && ( -e $dataFile2 );
	unlink $rmsFile2  if ( defined $rmsFile2 )  && ( -e $rmsFile2 );
	unlink $dataFile3 if ( defined $dataFile3 ) && ( -e $dataFile3 );
	unlink $rmsFile3  if ( defined $rmsFile3 )  && ( -e $rmsFile3 );
	unlink $plotFile  if ( defined $plotFile )  && ( -e $plotFile );
}
