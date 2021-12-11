#!/bin/perl

use warnings;
use strict;

#convert <audio>.1
# to <audio>.2 using loudnorm
# to <audio>.3 using <filter>
# and compare

my $ffmpeg= "$ENV{HOME}/ffmpeg/bin/ffmpeg";

my $ladspa_plugin = 'ebur128-leveler-6s';
my $label = $ladspa_plugin =~ s/-/_/gr;
$ladspa_plugin .= ":$label";
#^ ebur128-leveler-6s:ebur128_leveler_6s

my ($d) = $ladspa_plugin =~ /([\d\.])+s/;
my $dh = $d / 2.0;
#^ 6s / 2 = 3

sub execute {
    my $command = shift;
    print STDERR "execute: $command\n";
    system($command);
    my $exitCode = $? >> 8;
    die("ERROR: $command died with error $exitCode: $!") if $exitCode;
}

my $input = $ARGV[0] || '';
exit print STDERR "missing file\n" if $input eq '';
execute "perl loudnorm.pl --file $input.1" unless -e "$input.2";

execute "cd $ENV{HOME}/radio/build/rms-leveler/rms-leveler/; make && sudo cp *.so /usr/lib/ladspa/";
execute "LADSPA_PATH=/usr/lib/ladspa $ffmpeg -y -i $input.1 -af ladspa=$ladspa_plugin -acodec pcm_s24le -ar 44100 $input.rms.wav";
execute "sox $input.rms.wav $input.trim.wav trim ".$dh; # shift half buffer duration left
execute "sox $input.trim.wav $input.pad.wav pad 0 ".$dh;
execute "cp $input.pad.wav $input.3";
unlink "$input.rms.wav";
unlink "$input.pad.wav";
unlink "$input.trim.wav";
execute "perl compare-rms.pl -i $input -r 0.3";
