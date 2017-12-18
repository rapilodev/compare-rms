#!/bin/perl

use warnings;
use strict;

sub error {
	print "ERROR: " . $_[0] . "\n";
	exit 1;
}

sub execute {
	my $command = shift;
	print STDERR "execute: $command\n";
	system($command);
	my $exitCode = $? >> 8;
	if ($exitCode != 0){
		error("$command died with error $exitCode: $!");
		exit 1;
	};
}

my $input = $ARGV[0] || '';
if ( $input eq '' ) {
	print STDERR "missing file\n";
	exit 1;
}

my $content = qq{
set("log.file", false)
set("log.stdout", true)
input = "$input.1"
output = "$input.3"
source = once(single(input))
source = ladspa.rms_leveler_6s(source)
clock.assign_new(sync=false,[source])
output.file( 
    \%wav(stereo=true, channels=2, samplesize=24, header=true), 
    output, fallible=true, on_stop=shutdown,source
)
};

open my $file, '>convert.liq';
print $file $content;
close $file;

#my $command="cd ~/radio/build/rms-leveler/rms-leveler-0.01.0043; make && sudo cp rmsL*.so /usr/lib/ladspa/";
#execute($command);

$command = "liquidsoap convert.liq";
execute($command);

$command = "sox $input.3 $input.trim.wav trim 3";
execute($command);

$command = "mv $input.trim.wav $input.3";
execute($command);

$command = "perl compareRms.pl -i $input -r 0.1 --no-delete";
execute($command);

