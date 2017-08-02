#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;

require 'sys/ioctl.ph';

#use Data::Dumper;

#########################
#        CONFIG         #
#########################

our $REG = {
	"stats" => {
		"filename" => "resourceagent",
		"reg_groups" => {
			"inactive" => [
				'DBG|MSG',
			],
		}
	},
};

#########################
#   HELPER FUNCTIONS    #
#########################

sub matchTailFilename ($) {
	my $line = shift;

	if ( $line =~ '^==> (.*) <==$' ) {
		return $1;
	}
}

sub matchFile ($) {
	my $file = shift;

	foreach my $reg_file_group (keys %$REG) {
		if ( $file =~ $REG->{$reg_file_group}->{filename} ) {
			return $reg_file_group;
		}
	}
}

sub matchGroup ($$) {
	my $line = shift;
	my $file = shift;

	our $REG;
	my $filematch;
	if (! ( $filematch = matchFile($file) )) {
		return;
	}

	foreach my $reg_group (keys %{$REG->{$filematch}->{reg_groups}}) {
		if ( $line =~ $REG->{$filematch}->{reg_groups}->{$reg_group} ) {
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
	our $REG;

	foreach my $reg_file_group (keys %$REG) {

		foreach my $reg_group (keys %{$REG->{$reg_file_group}->{reg_groups}}) {
			my $reg_str = '(';
			my $first = 1;

			foreach my $reg ( @{ $REG->{$reg_file_group}->{reg_groups}->{$reg_group} } ) {
				if ($first) {
					$first=0;
				} else {
					$reg_str .= '|';
				}

				$reg_str .= $reg;
			}
			$reg_str .= ")";
			$REG->{$reg_file_group}->{reg_groups}->{$reg_group} = qr/$reg_str/;
		}
	}
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

	my $start = $#BUFFER - ($rows-2, $#BUFFER)[$rows-2 > $#BUFFER];
	my $end = $#BUFFER;
	for ( my $linenum=$start; $linenum <= $end; $linenum++ ) {
		$chars .= "\n ";
		if (length($BUFFER[$linenum][2]) <= 30) {
			$chars .= sprintf ( "%-30s", $BUFFER[$linenum][2]);
		} else {
			$chars .= "..." . substr ( $BUFFER[$linenum][2], -27 );
		}
		$chars .= " | $BUFFER[$linenum][0]";
		$chars .= " \e[1m(" . ($BUFFER[$linenum][1]+1) . ")\e[0m" if $BUFFER[$linenum][1];
	}
	print $chars;
}

sub proccessLine ($) {
	our ($COUNT, $CUR_FILE, $SKIPPED, @BUFFER, $AGGREGATED, $LAST_POS_INDEX);
	my $line = shift;


	chomp( $line );

	# IGNORE EMPTY LINES
	return if ($line =~ '^$');

	# MATCH TAIL FILENAME LINES
	if (my $f = matchTailFilename($line)) {
		$CUR_FILE = $f;
		return;
	}
	$COUNT++;
	my $match = matchGroup($line, $CUR_FILE);

	if ($match) {
		# SKIP LINES THAT MATCH CERTAIN GROUPS
		if (skipLine($match)) {
			$SKIPPED++;
			return;
		}

		# PROCCESS THE REST OF THE LINES
		if ( defined $LAST_POS_INDEX->{$CUR_FILE} && defined $BUFFER[$LAST_POS_INDEX->{$CUR_FILE}][3] && $BUFFER[$LAST_POS_INDEX->{$CUR_FILE}][3] eq $match ) {
			$AGGREGATED++;

			push(@BUFFER, splice(@BUFFER, $LAST_POS_INDEX->{$CUR_FILE}, 1));
			$LAST_POS_INDEX->{$CUR_FILE} = $#BUFFER;
			updateIndices();

			$BUFFER[$#BUFFER][0]=$line;
			$BUFFER[$#BUFFER][1]++;
		} else {
			push @BUFFER, [$line, 0, $CUR_FILE];
			$LAST_POS_INDEX->{$CUR_FILE} = $#BUFFER;

			$BUFFER[$LAST_POS_INDEX->{$CUR_FILE}][3] = $match;
		}
	} else {
		push @BUFFER, [$line, 0, $CUR_FILE];
		$LAST_POS_INDEX->{$CUR_FILE} = $#BUFFER;
	}
}

sub updateIndices () {
	our ($TO_PRINT, @BUFFER, $LAST_POS_INDEX);
	print STDERR "from " . ($TO_PRINT-1) . " to 0\n";
	for ( my $linenum=$TO_PRINT-1; $linenum >= 0; $linenum-- ) {
		print STDERR "Changing LAST_POS_INDEX for file " . $BUFFER[$#BUFFER-$linenum][2] . " to " . ($#BUFFER-$linenum) ."\n";
		$LAST_POS_INDEX->{$BUFFER[$#BUFFER-$linenum][2]} = $#BUFFER-$linenum;
	}
}

#########################
#         INIT          #
#########################

$SIG{INT} = sub { print "\e[?1049l" };

$|=1;

our $OMMIT_GROUPS = [  ];

compileRegs();

our @BUFFER;
our $LAST_POS_INDEX = {};
our $CUR_FILE;

our $COUNT = 0;
our $AGGREGATED = 0;
our $SKIPPED = 0;

print "\e[?1049h";

#########################
#         MAIN          #
#########################

while (my $line = readline(*STDIN) ) {
	proccessLine($line);
	printLines();
}

print "\e[?1049l";
