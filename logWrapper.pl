#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;

use Time::HiRes qw( usleep );
use Switch;

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

sub quit {
	our $termCon;

	$termCon->endAlternate();
	exit;
}

sub terminalUpdated {
	our $termCon;
	our $refresh;

	$termCon->updateWinsize();
	$refresh = 1;
}

#########################
#         INIT          #
#########################

$|=1;

our $refresh = 0;

my $buffCon = BufferControl->new($REG, $OMMIT_GROUPS);
our $termCon = TerminalControl->new($buffCon, "/dev/tty");

my $in = Stream->new(*STDIN);

$SIG{INT} = \&quit;
$SIG{WINCH} = \&terminalUpdated;

#########################
#         MAIN          #
#########################

$termCon->startAlternate();

while (1) {
	foreach my $c (@{$termCon->getCommands()}) {
		switch ($c) {
			case 'quit'        { quit() }
			case "separator"   { $buffCon->addSeparator(); }
			case "up"          { $termCon->scroll(-1); }
			case "down"        { $termCon->scroll(1); }
			case "pageUp"      { $termCon->scroll(-10); }
			case "pageDown"    { $termCon->scroll(10); }
			case "end"         { $termCon->scroll(); }
			case "invalid"         { print STDERR "Invalid command received\n" }
			#print STDERR "0x$_ " for unpack "(H2)*",$opt; print STDERR "\n";
		}
	}

	if ( $in->readLine ) {
		$buffCon->proccessLine($in->getData());
	}
	$termCon->output($refresh);
	$refresh = 0;
	usleep(100);
}

$termCon->endAlternate();
