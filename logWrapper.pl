#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;

use Time::HiRes qw( usleep );
use Switch;
use Linux::Inotify2;
use File::Find;

use TerminalControl;
use BufferControl;
use Stream;

use Data::Dumper;

#########################
#        CONFIG         #
#########################

our $FILE_GROUPS = {
	# The regex that will match the filename
	'syslog_auth' => [ '(auth.log|syslog)' ],
	'auth' => [ 'auth.log' ],
	'stats' => [ '(resourceagent|clustermanager)_[0-9]*\.log' ],
	'ocperf' => [ 'ocperf_ag_[0-9]*\.log' ],
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

	'Cron' => {
		'files' => 'syslog_auth',
		'regs' => [ 'CRON\[[0-9]*\]:' ]
	},
};

# This is the regex configuration
our $COLOR_REG = {
	"Timestamps" => {

		"files" => 'stats',
		"color" => '118',
		"regs" => [
			'(^[^,]*)',
		],
	},
	"Timestamps2" => {

		"files" => 'ocperf',
		"color" => '118',
		"regs" => [
			'^\(([^\)]*)\)',
		],
	},
	'ProcName' => {
		'files' => 'syslog_auth',
		'color' => '64',
		'regs' => [ '[0-9]{2}:[0-9]{2}[^ ]* [^ ]* ([^:\[]*)' ]
	},
	'ProcID' => {
		'files' => 'syslog_auth',
		'color' => '160',
		'regs' => [ '[0-9]{2}:[0-9]{2}[^ ]* [^ ]* [^\[]*\[([0-9]*)\]' ]
	},
};

# Any reg_groups from above that are found in this array will be skipped entierly
our $OMMIT_GROUPS = [  ];

#########################
#   HELPER FUNCTIONS    #
#########################

sub quit {
	our $termCon;

	our $buffCon;

	#print STDERR Dumper($buffCon);
	$termCon->endAlternate();
	exit;
}

sub terminalUpdated {
	our $termCon;
	our $refresh;

	$termCon->updateWinsize();
	$refresh = 1;
}

my $inotify;
sub handleFile {
	our @inStreams;
	my $file = shift;
	if (-d $file) {
		print STDERR "Found DIR $file. \n";
		$inotify->watch (
			$file,
			IN_CREATE,
			sub {
				my $e = shift;
				find(
					sub {
						handleFile($File::Find::name);
					},
					$e->fullname
				);
			}
		);
	} else {
		print STDERR "Found FILE $file. Adding...\n";
		push @inStreams, Stream->new($file);
	}
}

#########################
#         INIT          #
#########################

$|=1;

our $refresh = 0;

our $buffCon = BufferControl->new($AGGREGATE_REG, $COLOR_REG, $FILE_GROUPS, $OMMIT_GROUPS);
our $termCon = TerminalControl->new($buffCon, "/dev/tty");

our @inStreams = ();

$inotify = new Linux::Inotify2 or die "unable to create new inotify object: $!";
$inotify->blocking (0);

foreach my $file (@ARGV) {
	if (-d $file) {
		find(sub { handleFile($File::Find::name); }, $file);
	} else {
		push @inStreams, Stream->new($file);
	}
}

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

	foreach my $stream (@inStreams) {
		if ( $stream->read() ) {
			$buffCon->proccessLines($stream->getLines(), $stream->{file});
		}
	}
	$termCon->output($refresh);
	$refresh = 0;
	$inotify->poll;
	usleep(100);
}

$termCon->endAlternate();
