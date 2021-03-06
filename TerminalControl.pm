package TerminalControl;

use 5.010;
use strict;
use warnings;
use Term::ReadKey;

require 'sys/ioctl.ph';

# Package: TerminalControl
#   This package provides the means to construct the data to be output to the
#   terminal, including the text itself and the required control sequences (
#   cursor movement, clearing lines, etc)


# The following are the control sequences used here
#   SAVE CURSOR POS           = \e[s
#   RESTORE CURSOR POS        = \e[u
#   SET POSITION              = \e[1;1H
#   CLEAR TO THE END OF LINE  = \e[K
#   ALTERNATE SCREEN          = \e[?1049h
#   EXIT ALTERNATE SCREEN     = \e[?1049l
#   REVERSE LINE FEED =       = \eM

# * output
#   * constructLines
#     * Print Above Screen
#     * Print Below Screen
#     * Did we mess anything in the above two steps?
#       * Mark lines that need updating
#     * Update Lines (Either because they were updated by the buffer or because they have overlays)
#         The actual update is performed from the first line that needs updating, to the last line before the newly added.
#       * Insert overlay blocks   !!! TODO: The colorize function should work with ranges.
#
#
#

#########################
#         INIT          #
#########################

our $parse = {
	"\e" => {
		"[" => {
			"A" => "up",
			"B" => "down",
			"5" => {
				"~" => "pageUp", },
			"6" => {
				"~" => "pageDown", }, },
		"O" => {
			"F" => "end", }, },
	"q" => "quit",
	"\n" => "separator",
};

#############################
#   TERMINAL INTERFACING    #
#############################

sub startAlternate {
	# Enter the alternate screen mode
	print "\e[?1049h";
}

sub endAlternate {
	# Exit the alternate screen
	print "\e[?1049l";

	# Reset the NOECHO that was set earlier
	ReadMode ( 0, *STDOUT );
}

sub updateWinsize {
	my $self = shift;

	my $winsize = "";
	if (ioctl(STDOUT, TIOCGWINSZ() , $winsize)) {
		# Provide the size of the terminal, both in chars and pixels: (rows, cols, pixelsX, pixlesY)
		($self->{rows}, $self->{cols}) = unpack 'S4', $winsize;
	}
}

sub clrLine {
	my $self = shift;
	my $chars = \$self->{chars};

	$$chars .= "\e[K";
}

sub cls {
	my $self = shift;
	my $chars = \$self->{chars};

	$$chars .= "\e[2J";
}

sub nl {
	my $self = shift;
	my $chars = \$self->{chars};

	$$chars .= "\n";
}

sub revNl {
	my $self = shift;
	my $chars = \$self->{chars};

	$$chars .= "\eM";
}

sub mvCur ($$) {
	my $self = shift;
	my ($r,$c) = @_;

	my $chars = \$self->{chars};

	# If a provided value is negative, start counting from the end with -1 being the last line/char
	$r = $self->{rows} + $r +1 if ($r < 0);
	$c = $self->{cols} + $c +1 if ($c < 0);

	$$chars .= "\e[".$r.";".$c."H";
}

sub print {
	my $self = shift;

	my $chars = \$self->{chars};
	print $$chars;
	$$chars = '';
}

#############################
#  METHODS FOR PREPARATION  #
#############################

sub new ($$) {
	my $class = shift;
	my $buffCon = shift;
	my $in = shift;
	our $parse;

	my $self = { 'buffCon' => $buffCon, # Used to store a BufferControler object
	             'chars' => '', # The character buffer used for preparation before printing
	             'follow' => 1,
	             'endPos' => -1,
	             'changed' => 0,
	             'newEndPos' => -1,
	             'in' => Stream->new($in, 1),
	             'inBuff' => '',
	             'parsePos' => $parse,
	             'parse' => $parse,
	           };

	bless $self, $class;

	$self->updateWinsize();

	return $self;
}

sub colorize () {
	my $self = shift;
	my $text = shift;
	my $colorMap = shift;
	my $colorOffset = shift;
	my $colorLen = shift;

	my $curFile = \$self->{curFile};

	foreach my $c (grep {$_->[0] < $colorLen} @{$colorMap}) {
		my $code = ($c->[1] < 0 ? "\e[0m" : "\e[38;5;".$c->[1]."m");
		substr($$text, $c->[0] + $colorOffset, 0) = $code;
	}
}

sub addLine ($$$) {
	my $self = shift;
	my $linenum = shift;
	my $lineRow = shift;
	my $lineCol = shift;

	$lineRow = $self->{rows} + $lineRow +1 if ($lineRow < 0);
	$lineCol = $self->{cols} + $lineCol +1 if ($lineCol < 0);

	my $fileColWidth = 16;

	$self->mvCur($lineRow, $lineCol);

	my $chars = \$self->{chars};

	if ($linenum < 0 || $linenum > (scalar @{$self->{buffCon}->{buff}})-1) {
		$self->clrLine();
		return;
	}

	my $line = $self->{buffCon}->{buff}->[$linenum];
	my $prepLine;
	my $isMeta = $line->[5];

	if ($isMeta) { # META LINE
		my $len = $self->{cols} - 1;
		$prepLine .= substr ($line->[0], 0, $len) . "\e[0m";
	} else { # NORMAL LINE
		if (length($line->[2]) <= $fileColWidth) {
			$prepLine = " " . sprintf ( '%-' . $fileColWidth . 's', $line->[2]);
		} else {
			$prepLine = " ..." . substr ( $line->[2], -$fileColWidth + 3 );
		}

		my $len = $self->{cols} - $fileColWidth - 4;
		$len -= length ( "" . ($line->[1]+1) ) + 3 if $line->[1];

		$prepLine .= " | " . substr ($line->[0], 0, $len) . "\e[0m";
		$prepLine .= " \e[1m(" . ($line->[1]+1) . ")\e[0m" if $line->[1];

		$self->colorize(\$prepLine, $line->[4], $fileColWidth + 4, $len);
	}

	$$chars .= $prepLine;
}

sub addHeader {
	my $self = shift;

	my $count = $self->{buffCon}->{count};
	my $skipped = $self->{buffCon}->{skipped};
	my $aggregated = $self->{buffCon}->{aggregated};

	my $chars = \$self->{chars};

	$self->mvCur(1, 1);
	$$chars .= "\e[30;43m Printed: " . ($count-$skipped-$aggregated) . " - Skipped: $skipped - Aggregated: $aggregated";
	$self->clrLine();
	$$chars .= "\e[0m";
}

sub constructLines {
	my $self = shift;
	my $refresh = shift;

	my $buff = $self->{buffCon}->{buff};
	my $updatesStart = \$self->{buffCon}->{updatesStart};
	my $endPos = \$self->{endPos};
	my $newEndPos = \$self->{newEndPos};
	my $follow = \$self->{follow};

	$$newEndPos = (scalar @{$buff})-1 if ($$follow == 1);

	if ($refresh == 1) {
		$self->cls();
		$$endPos = -1;
	}

	# If the range to be updated is larger than one screen, adjust the range so that
	# only the visible range is printed.
	if ($$newEndPos - $$endPos > $self->{rows} - 1) {
		$$endPos = $$newEndPos - ($self->{rows} - 1);
	} elsif ($$endPos - $$newEndPos > $self->{rows} - 1) {
		$$endPos = $$newEndPos + ($self->{rows} - 1);
	}

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
	# Print old lines outside of the buffer (above screen)        #
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
	#
	# While newEndPos is smaller than the current endPos
	#   Start from FirstInvisibleLineBefore to LastLineToPrint
	#
	#   FirstInvisibleLineBefore = FirstVisibleLine -1
	#   FirstVisibleLine = LastVisibleLine - (rows + 2)
	#   LastVisibleLine = endPos
	#     SO: FirstInvisibleLineBefore = endPos - rows + 1
	#
	#   LastLineToPrint = FirstVisibleLine - DiffBetweenPositions
	#   DiffBetweenPositions = endPos - newEndPos
	#     SO: LastLineToPrint = newEndPos - rows + 2
	for (my $linenum = $$endPos + 1 - $self->{rows}; $linenum >= $$newEndPos - $self->{rows} +2; $linenum--) {
		$self->mvCur(1, 1);
		$self->revNl();
		$self->addLine($linenum, 2, 1);
		$self->clrLine();
	}

	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
	# Print new lines by advancing the buffer                     #
	# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
	#
	# While newEndPos is greater than the current endPos
	#   Start from FirstInvisibleLineAfter to LastLineToPrint
	#
	#   FirstInvisibleLineAfter = FirstVisibleLine +1
	#   FirstVisibleLine = endPos
	#     SO: FirstInvisibleLineAfter = endPos + 1
	#
	#     SO: LastLineToPrint =  newEndPos
	for (my $linenum = $$endPos + 1; $linenum <= $$newEndPos; $linenum++) {
		$self->mvCur(-1, 1);
		$self->nl();
		$self->addLine($linenum, -1, 1);
		$self->clrLine();
	}

	# If we have a position from which we have to update lines that changed ...
	if (defined $$updatesStart) {

		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
		# Update existing lines without moving the buffer             #
		# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
		#
		# If ProcFrom is above FirstVisibleLine
		#   ProcFrom = FirstVisibleLine
		#   FirstVisibleLine = LastVisibleLine - (rows + 2)
		#     !! +2 because LastVisibleLine - rows = line 0
		#     !! and line 0 is the first non-visible line before the point where the terminal starts
		#   LastVisibleLine = newEndPos
		$$updatesStart = $$newEndPos - $self->{rows} + 2  if ( $$updatesStart < -$self->{rows} + $$newEndPos +2);
		for (my $linenum = $$updatesStart; $linenum <= $$newEndPos; $linenum++) {
			$self->addLine($linenum, $linenum-$$newEndPos-1, 0);
			$self->clrLine();
		}
	}


	$$updatesStart = undef;
	$$endPos = $$newEndPos;
}

sub scroll {
	my $self = shift;
	my $diff = shift;


	my $buff = $self->{buffCon}->{buff};
	my $newEndPos = \$self->{newEndPos};
	my $follow = \$self->{follow};

	$self->{changed} = 1;

	# If we have no position or position is larger than the buffer ...
	if ( (! defined $diff) || ( ($$newEndPos + $diff) > ((scalar @{$buff})-1) ) ) {
		# Go to the end
		$$newEndPos = (scalar @{$buff})-1;
	} elsif (($$newEndPos + $diff) < 0) { # If endPos is smaller than the start of buffer
		# Go to start
		$$newEndPos = 0;
	} else {
		# Apply the position change
		$$newEndPos += $diff;
	}

	# Follow any new lines if we are at the end
	if ($$newEndPos == (scalar @{$buff})-1) {
		$$follow = 1;
	} else {
		$$follow = 0;
	}

}

sub output {
	my $self = shift;
	my $refresh = shift;

	if ($self->{changed} || $self->{buffCon}->{changed} || $refresh == 1 ) {
		$self->constructLines($refresh);
		$self->addHeader();

		$self->print();
		$self->{changed} = 0;
		$self->{buffCon}->{changed} = 0;
	}
}

sub getCommands {
	my $self = shift;

	my $inBuff = \$self->{inBuff};
	my $parsePos = $self->{parsePos};
	my $parse = $self->{parse};
	my $char;
	my $commands = [];

	if ($self->{in}->read()) {
		$$inBuff .= $self->{in}->getData();


		while (length $$inBuff) {
			($char, $$inBuff) = split //, $$inBuff, 2;

			if (defined $parsePos->{$char}) {
				$parsePos = $parsePos->{$char};
				if ( ref($parsePos) eq 'HASH' ) {
				} else {
					push @$commands, $parsePos;
					$parsePos = $parse;
				}
			} else {
				push @$commands, "invalid";
				$parsePos = $parse;
			}
		}
	}
	return $commands;
}

1;
