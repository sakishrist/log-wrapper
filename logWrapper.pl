#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;

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

#########################
#         INIT          #
#########################

$|=1;

our $OMMIT_GROUPS = [  ];

our $REG_OBJ = {};
compileRegs();

my $COUNT = 0;
my $AGGREGATED = 0;
my $CURR_SKIPPED = 0;
my $SKIPPED = 0;

my $LAST_MATCH = "";

# clear
print "\e[2J\e[1;1H\n";

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
				$CURR_SKIPPED++;
				print "\r$line \e[1m(" . ($CURR_SKIPPED+1) . ")\e[0m\e[K";
			} else {
				print "\n" if ( $LAST_MATCH );
				print "$line";
				$CURR_SKIPPED = 0;
			}

			$LAST_MATCH = $match;
		} else {
			print "\n" if ( $LAST_MATCH );
			print "$line\n";
			$LAST_MATCH = "";
			$CURR_SKIPPED = 0;
		}
	}

	print "\e[s\e[1;1H\e[30;43m\e[KPrinted: " . ($COUNT-$SKIPPED-$AGGREGATED) . " - Skipped: $SKIPPED - Aggregated: $AGGREGATED\e[0m\e[u";

}

print "\n" if ( $LAST_MATCH );
