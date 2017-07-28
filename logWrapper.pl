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
		'cinnamon-screensaver-pam-helper',
	],
};

#########################
#   HELPER FUNCTIONS    #
#########################

sub compileRegs ($) {
	my ($REG_OBJ) = @_;

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

my $OMMIT_GROUPS = [  ];

my $REG_OBJ = {};
compileRegs ($REG_OBJ);

my $COUNT = 0;
my $AGGREGATED = 0;
my $CURR_SKIPPED = 0;
my $SKIPPED = 0;

my $LAST_MATCH = "";

# clear
print "\e[2J\e[1;1H\n";

MAIN_LOOP:
while (my $line = readline(*STDIN) ) {
	$COUNT++;
	chomp( $line );

	my $match = "";

	REG_MATCHING:
	foreach my $reg_group (keys %$REG) {
		if ( $line =~ $REG_OBJ->{main}->{$reg_group} ) {
			$match = $reg_group;
			last REG_MATCHING;
		}
	}

	foreach my $ommit_group (@$OMMIT_GROUPS) {
		if ( $ommit_group eq $match ) {
			$SKIPPED++;
			print "\e[s\e[1;1H\e[30;43m\e[KPrinted: " . ($COUNT-$SKIPPED-$AGGREGATED) . " - Skipped: $SKIPPED - Aggregated: $AGGREGATED\e[0m\e[u";
			next MAIN_LOOP;
		}
	}

	foreach my $ommit_proc (@{$REG_OBJ->{ommitProc}}) {
		if ( $line =~ $ommit_proc ) {
			$SKIPPED++;
			print "\e[s\e[1;1H\e[30;43m\e[KPrinted: " . ($COUNT-$SKIPPED-$AGGREGATED) . " - Skipped: $SKIPPED - Aggregated: $AGGREGATED\e[0m\e[u";
			next MAIN_LOOP;
		}
	}

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

	print "\e[s\e[1;1H\e[30;43m\e[KPrinted: " . ($COUNT-$SKIPPED-$AGGREGATED) . " - Skipped: $SKIPPED - Aggregated: $AGGREGATED\e[0m\e[u";

}
