#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;
use Time::HiRes qw( usleep );

use TerminalControl;
use BufferControl;
use Stream;

#use Data::Dumper;

#########################
#        CONFIG         #
#########################

# This is the regex configuration
our $REG = {
	# Regex rules can be specified for specific files depending on their names.
	"stats" => {

		# This is a regex to match the filename
		"filename" => "file",

		# Regexes can be groupped together. This enables the aggregation into separate
		# lines if they are from different groups.
		"reg_groups" => {
			"inactive" => [
				'file',
			],
		}
	},
};

# Any reg_groups from above that are found in this array will be skipped entierly
our $OMMIT_GROUPS = [  ];

#########################
#   HELPER FUNCTIONS    #
#########################

sub end { our $termCon; $termCon->endAlternate(); exit; };

#########################
#         INIT          #
#########################

$|=1;

my $buffCon = BufferControl->new($REG, $OMMIT_GROUPS);
our $termCon = TerminalControl->new($buffCon);

my $in = Stream->new(*STDIN);
my $term = Stream->new("/dev/tty", 1);

$SIG{INT} = \&end;

#########################
#         MAIN          #
#########################

$termCon->startAlternate();

while (1) {
	if ($term->readChar()) {
		my $seq = $term->getData();
		end() if ( $seq eq 'q' );
		if ( $seq eq "\n" ) {
			$buffCon->addSeparator();
			$termCon->output();
		}
		if ( $seq eq "w" ) {
			$termCon->scroll(-1);
		}
		if ( $seq eq "s" ) {
			$termCon->scroll(1);
		}
	}

	if ( $in->readLine ) {
		$buffCon->proccessLine($in->getData());
	}
	$termCon->output();
	usleep(100);
}

$termCon->endAlternate();
