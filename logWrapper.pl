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

our $FILE_GROUPS = {
	# The regex that will match the filename
	'stats' => [ '(resourceagent|clustermanager)_[0-9]*\.log' ],
};

# This is the regex configuration
our $AGGREGATE_REG = {
	# Name for the group that will aggregate lines
	"Stat debugs" => {

		# This is a regex group to match the filename
		"files" => 'stats',

		# Regexes that if matched will aggregate the line into a previous one that
		# has matched the same group.
		"regs" => [
			'DBG',
		],
	},
};

# This is the regex configuration
our $COLOR_REG = {
	"MSG" => {

		"files" => 'stats',
		"color" => '118',
		"regs" => [
			', (MSG):\t',
		],
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

my $buffCon = BufferControl->new($AGGREGATE_REG, $COLOR_REG, $FILE_GROUPS, $OMMIT_GROUPS);
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
