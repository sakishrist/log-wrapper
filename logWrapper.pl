#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;

#use Data::Dumper;

#########################
#        CONFIG         #
#########################

our $REG = {
	"stats" => {
		"filename" => "file",
		"reg_groups" => {
			"inactive" => [
				'file',
			],
		}
	},
};

our $OMMIT_GROUPS = [  ];

#########################
#       PACKAGES        #
#########################

# Package: termControl
{
	package TerminalControl;

	use 5.010;
	use strict;
	use warnings;

	require 'sys/ioctl.ph';

	# SAVE = \e[s
	# RESTORE = \e[u
	# SET POSITION = \e[1;1H
	# CLEAR LINE = \e[K

	sub new ($) {
		my $class = shift;
		my $buffCon = shift;
		my $self = { 'buffCon' => $buffCon,
		             'chars' => '', };

		bless $self, $class;

		($self->{rows}, $self->{cols}) = $self->getwinsize();

		return $self;
	}

	sub startAlternate { print "\e[?1049h"; }
	sub endAlternate { print "\e[?1049l"; }

	sub getwinsize {
		my $winsize = ""; # Silence warning
		if (ioctl(STDOUT, TIOCGWINSZ() , $winsize)) {
			return unpack 'S4', $winsize;
		}
	}

	sub clrLine {
		my $self = shift;
		my $chars = \$self->{chars};

		$$chars .= "\e[K";
	}

	sub nl {
		my $self = shift;
		my $chars = \$self->{chars};

		$$chars .= "\n";
	}

	sub mvCur ($$) {
		my $self = shift;
		my ($r,$c) = @_;

		my $chars = \$self->{chars};

		$r = $self->{rows} + $r +1 if ($r < 0);
		$c = $self->{cols} + $c +1 if ($c < 0);

		$$chars .= "\e[".$r.";".$c."H";
	}

	sub addLine ($) {
		my $self = shift;
		my $linenum = shift;

		my $chars = \$self->{chars};
		my $line = $self->{buffCon}->{buff}->[$linenum];

		if (length($line->[2]) <= 30) {
			$$chars .= " " . sprintf ( "%-30s", $line->[2]);
		} else {
			$$chars .= " ..." . substr ( $line->[2], -27 );
		}

		$$chars .= " | " . $line->[0];
		$$chars .= " \e[1m(" . ($line->[1]+1) . ")\e[0m" if $line->[1];
	}

	sub addHeader {
		my $self = shift;

		my $count = $self->{buffCon}->{count};
		my $skipped = $self->{buffCon}->{skipped};
		my $aggregated = $self->{buffCon}->{aggregated};

		my $chars = \$self->{chars};

		$$chars .= "\e[1;1H\e[30;43m Printed: " . ($count-$skipped-$aggregated) . " - Skipped: $skipped - Aggregated: $aggregated\e[K\e[0m";
	}

	sub constructLines () {
		my $self = shift;

		my $buff = $self->{buffCon}->{buff};
		my $toPrint = \$self->{buffCon}->{toPrint};

		if ($$toPrint == 0 || $$toPrint > $self->{rows}-2) {
			$self->mvCur(-1, -1);
			$self->nl();
			$self->addLine((scalar @{$buff})-1);
		} elsif ($$toPrint > 0) {
			# FIXME I might have messed up the math here
			mvCur(-1 - $$toPrint, -1);
			for ( my $linenum=$$toPrint-1; $linenum >= 0; $linenum-- ) {
				$self->nl();
				$self->addLine(((scalar @{$buff})-1)-$linenum);
				$self->clrLine();
			}
		} else {
			return;
		}
	}

	sub output {
		my $self = shift;

		$self->constructLines();
		$self->addHeader();

		$self->print();
	}

	sub print {
		my $self = shift;

		my $chars = \$self->{chars};
		print $$chars;
		$$chars = '';
	}

}

# Package: BufferControl
{
	package BufferControl;

	use 5.010;
	use strict;
	use warnings;
	use IO::Select;

	sub new ($$) {
		my $class = shift;
		my $reg = shift;
		my $omit = shift;

		my $self = {
		             'buff' => [],
		             'count' => 0,
		             'skipped' => 0,
		             'aggregated' => 0,
		             'toPrint' => 0,
		             'curFile' => '',
		             'lastPosIndex' => {},
		             'reg' => $reg,
		             'omit' => $omit,
		             'stdin' => IO::Select->new(),
		           };

		bless $self, $class;

		$self->{stdin}->add(\*STDIN);
		$self->compileRegs();

		return $self;
	}

	sub skipLine ($) {
		my $self = shift;
		my $match = shift;

		my $omit = $self->{omit};

		foreach my $omit_group (@{$omit}) {
			if ( $omit_group eq $match ) {
				return 1;
			}
		}
		return 0;
	}

	sub compileRegs () {
		my $self = shift;

		my $reg = $self->{reg};

		foreach my $reg_file_group (keys %{$reg}) {

			foreach my $reg_group (keys %{$reg->{$reg_file_group}->{reg_groups}}) {
				my $reg_str = '(';
				my $first = 1;

				foreach my $r ( @{ $reg->{$reg_file_group}->{reg_groups}->{$reg_group} } ) {
					if ($first) {
						$first=0;
					} else {
						$reg_str .= '|';
					}

					$reg_str .= $r;
				}
				$reg_str .= ")";
				$reg->{$reg_file_group}->{reg_groups}->{$reg_group} = qr/$reg_str/;
			}
		}
	}

	sub updateIndices () {
		my $self = shift;

		my $buff = $self->{buff};
		my $toPrint = \$self->{toPrint};
		my $lastPosIndex = $self->{lastPosIndex};

		for ( my $linenum=$$toPrint-1; $linenum >= 0; $linenum-- ) {
			$lastPosIndex->{$buff->[(scalar @{$buff})-$linenum-1][2]} = (scalar @{$buff})-$linenum-1;
		}
	}

	sub matchTailFilename ($) {
		my $self = shift;
		my $line = shift;

		if ( $line =~ '^==> (.*) <==$' ) {
			return $1;
		}
	}

	sub matchFile ($) {
		my $self = shift;
		my $file = shift;

		my $reg = $self->{reg};

		foreach my $reg_file_group (keys %{$reg}) {
			if ( $file =~ $reg->{$reg_file_group}->{filename} ) {
				return $reg_file_group;
			}
		}
	}

	sub matchGroup ($$) {
		my $self = shift;
		my $line = shift;
		my $file = shift;

		my $filematch;
		if (! ( $filematch = $self->matchFile($file) )) {
			return;
		}

		my $regGroups = $self->{reg}->{$filematch}->{reg_groups};

		foreach my $reg_group (keys %{$regGroups}) {
			if ( $line =~ $regGroups->{$reg_group} ) {
				return $reg_group;
			}
		}
	}

	sub proccessLine ($) {
		my $self = shift;
		my $line = shift;

		my $curFile = \$self->{curFile};
		my $buff = $self->{buff};
		my $count = \$self->{count};
		my $toPrint = \$self->{toPrint};
		my $skipped = \$self->{skipped};
		my $aggregated = \$self->{aggregated};
		my $posIndex = \$self->{lastPosIndex}->{$$curFile};


		chomp( $line );

		$$toPrint = -1;
		# IGNORE EMPTY LINES
		return if ($line =~ '^$');

		# MATCH TAIL FILENAME LINES
		if (my $f = $self->matchTailFilename($line)) {
			$$curFile = $f;
			return;
		}
		$$count++;
		my $match = $self->matchGroup($line, $$curFile);

		if ($match) {
			# SKIP LINES THAT MATCH CERTAIN GROUPS
			if ($self->skipLine($match)) {
				$$skipped++;
				return;
			}

			# PROCCESS THE REST OF THE LINES
			if ( defined $$posIndex && defined $buff->[$$posIndex][3] && $buff->[$$posIndex][3] eq $match ) {
				$$aggregated++;

				$$toPrint = ((scalar @{$buff})-1) - $$posIndex + 1;
				push(@{$buff}, splice(@{$buff}, $$posIndex, 1));
				$$posIndex = (scalar @{$buff})-1;

				$self->updateIndices();

				$buff->[(scalar @{$buff})-1][0]=$line;
				$buff->[(scalar @{$buff})-1][1]++;
			} else {
				$$toPrint = 0;

				push(@{$buff}, [$line, 0, $$curFile, $match]);
				$$posIndex = (scalar @{$buff})-1;

				$buff->[$$posIndex][3] = $match;
			}
		} else {
			$$toPrint = 0;

			push(@{$buff}, [$line, 0, $$curFile]);
			$$posIndex = (scalar @{$buff})-1;
		}
	}

	sub readLine() {
		my $self = shift;

		if ( $self->{stdin}->can_read(1) ) {
			my $line;
			return 0 if ! ( defined ($line = readline(*STDIN)) );
			$self->proccessLine($line);
			return 1;
		}
	}
}

#########################
#   HELPER FUNCTIONS    #
#########################

#########################
#         INIT          #
#########################

$|=1;

my $buffCon = BufferControl->new($REG, $OMMIT_GROUPS);
my $termCon = TerminalControl->new($buffCon);

$SIG{INT} = sub { $termCon->endAlternate(); };

#########################
#         MAIN          #
#########################

$termCon->startAlternate();

while (1) {
	$buffCon->readLine() or last;
	$termCon->output();
}

$termCon->endAlternate();
