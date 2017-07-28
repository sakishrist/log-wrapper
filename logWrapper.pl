#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;

require 'sys/ioctl.ph';

#use Data::Dumper;

#########################
#        CONFIG         #
#########################

my $REG = {
	"object_recovery" => [
		'CRON\[',
	],
};

#########################
#   HELPER FUNCTIONS    #
#########################

sub matchGroup ($) {
	my $line = shift;
	our $REG_OBJ;

	foreach my $reg_group (keys %$REG) {
		if ( $line =~ $REG_OBJ->{main}->{$reg_group} ) {
			return $reg_group;
		}
	}
}

sub skipLine ($) {
	my $match = shift;
	our $OMMIT_GROUPS;

	foreach my $ommit_group (@$OMMIT_GROUPS) {
		if ( $ommit_group eq $match ) {
			return 1;
		}
	}
	return 0;
}

sub compileRegs () {
	our $REG_OBJ;

	# COMPILE MAIN
	$REG_OBJ->{main} = {};
	foreach my $reg_group (keys %$REG) {
		my $reg_str = '(';
		my $first = 1;

		foreach my $reg ( @{ $REG->{$reg_group} } ) {
			if ($first) {
				$first=0;
			} else {
				$reg_str .= '|';
			}

			$reg_str .= $reg;
		}
		$reg_str .= ")";
		$REG_OBJ->{main}->{$reg_group} = qr/$reg_str/;
	}

	#print Dumper($REG_OBJ) . "\n";
	#exit 0;
}

sub getwinsize {
	my $winsize = ""; # Silence warning
	if (ioctl(STDOUT, TIOCGWINSZ() , $winsize)) {
		return unpack 'S4', $winsize;
	}
}

sub printLines () {
	our ($COUNT, $SKIPPED, $AGGREGATED, @BUFFER);
	my $chars;
	my ($rows, $cols) = getwinsize();

	# clear
	$chars .= "\e[2J\e[1;1H\n";

	# SAVE = \e[s
	# RESTORE = \e[u
	# SET POSITION = \e[1;1H
	# CLEAR LINE = \e[K
	$chars .= "\e[1;1H\e[30;43m Printed: " . ($COUNT-$SKIPPED-$AGGREGATED) . " - Skipped: $SKIPPED - Aggregated: $AGGREGATED\e[K\e[0m";
	print "rows: $rows; BUFFER: $#BUFFER; min: " . (($rows-2, $#BUFFER)[$rows-2 > $#BUFFER]) . "\n";
	my $start = $#BUFFER - ($rows-2, $#BUFFER)[$rows-2 > $#BUFFER];
	my $end = $#BUFFER;
	for ( my $linenum=$start; $linenum <= $end; $linenum++ ) {
		$chars .= "\n$BUFFER[$linenum][0]";
		$chars .= " \e[1m(" . ($BUFFER[$linenum][1]+1) . ")\e[0m" if $BUFFER[$linenum][1];
	}
	print $chars;
}

#########################
#         INIT          #
#########################

$|=1;

our $OMMIT_GROUPS = [  ];

our $REG_OBJ = {};
compileRegs();

our @BUFFER;

our $COUNT = 0;
our $AGGREGATED = 0;
our $SKIPPED = 0;

my $LAST_MATCH = "";

while (my $line = readline(*STDIN) ) {
	$COUNT++;
	chomp( $line );

	my $match = matchGroup($line);

	if (skipLine($match)) {
		$SKIPPED++;
	} else {
		if ($match) {
			if ( $LAST_MATCH eq $match ) {
				$AGGREGATED++;

				$BUFFER[$#BUFFER][0]=$line;
				$BUFFER[$#BUFFER][1]++;

			} else {
				push @BUFFER, [$line, 0]
			}

			$LAST_MATCH = $match;
		} else {
			push @BUFFER, [$line, 0];
			$LAST_MATCH = "";
		}
	}

	printLines();
}
