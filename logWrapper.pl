#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;
use Time::HiRes qw( usleep );

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
	use Term::ReadKey;

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
	sub endAlternate { print "\e[?1049l"; ReadMode ( 0, *STDOUT ); }

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
		my $procFrom = \$self->{buffCon}->{procFrom};
		my $procedTo = \$self->{buffCon}->{procedTo};

		if (defined $$procFrom) {
			$$procFrom = $$procedTo - $self->{rows} + 2 if ($$procedTo - $$procFrom +2 > $self->{rows});
			for (my $linenum = $$procFrom; $linenum <= $$procedTo; $linenum++) {
				$self->mvCur($linenum-$$procedTo-1, 0);
				$self->addLine($linenum);
				$self->clrLine();
			}
		}

		for (my $linenum = $$procedTo + 1; $linenum <= (scalar @{$buff})-1; $linenum++) {
			$self->mvCur(-1, 0);
			$self->nl();
			$self->addLine($linenum);
		}

		$$procFrom = undef;
		$$procedTo = (scalar @{$buff})-1;
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
		             'procFrom' => undef,
		             'procedTo' => -1,
		             'curFile' => '',
		             'lastPosIndex' => {},
		             'reg' => $reg,
		             'omit' => $omit,
		           };

		bless $self, $class;

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
		my $procFrom = \$self->{procFrom};
		my $lastPosIndex = $self->{lastPosIndex};

		for ( my $linenum=$procFrom; $linenum <= (scalar @{$buff})-1; $linenum++ ) {
			$lastPosIndex->{$buff->[$linenum][2]} = (scalar @{$buff})-$linenum-1;
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
		my $procFrom = \$self->{procFrom};
		my $skipped = \$self->{skipped};
		my $aggregated = \$self->{aggregated};
		my $posIndex = \$self->{lastPosIndex}->{$$curFile};

		chomp( $line );

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

				$$procFrom = $$posIndex;
				push(@{$buff}, splice(@{$buff}, $$posIndex, 1));
				$$posIndex = (scalar @{$buff})-1;

				$self->updateIndices();

				$buff->[(scalar @{$buff})-1][0]=$line;
				$buff->[(scalar @{$buff})-1][1]++;
			} else {
				push(@{$buff}, [$line, 0, $$curFile, $match]);
				$$posIndex = (scalar @{$buff})-1;

				$buff->[$$posIndex][3] = $match;
			}
		} else {
			push(@{$buff}, [$line, 0, $$curFile]);
			$$posIndex = (scalar @{$buff})-1;
		}
	}

	sub addSeparator () {
		my $self = shift;

		my $buff = $self->{buff};

		push(@{$buff}, ["", 0, ""]);
	}
}

# Package: Stream
{
	package Stream;

	use 5.010;
	use strict;
	use warnings;
	use IO::Select;
	use Term::ReadKey;

	sub new {
		my $class = shift;
		my $thing = shift;
		my $cbreak = shift;
		$cbreak = 0 if ! ( defined($cbreak) );

		my $self = {
		             'data' => '',
		             'file' => '',
		             'cbreak' => $cbreak,
		             'select' => IO::Select->new(),
		           };

		bless $self, $class;

		my $fd;

		if ( ref(\$thing) eq 'GLOB' ) {
			$self->{fd} = $thing;
			$fd = $thing;
		} else {
			open $fd, "<", $thing or die;
		}

		ReadMode ( 3, *$fd ) if ($cbreak);
		$self->{fd} = $fd;
		$self->{select}->add(\*$fd);
		$self->{isopen} = 1;

		return $self;
	}

	sub readLine() {
		my $self = shift;

		my $fd = $self->{fd};

		if ( $self->{select}->can_read(0) ) {
			# I should be able to read ...
			if ( defined (my $d = readline(*$fd)) ) {
				# I just read ...
				$self->{data} .= $d;
				return 1;
			} else {
				$self->{isopen} = 0;
			}
		}

		# Apparently no data is waiting to be read
		return 0;
	}

	sub readChar() {
		my $self = shift;

		my $fd = $self->{fd};
		#ReadMode ( 3, *$fd ) if ($self->{cbreak});
		while ( $self->{select}->can_read(0) ) {
			# I should be able to read ...
			my $d;
			if ( sysread(*$fd, $d, 1024) ) {
				# I just read ...
				$self->{data} = $d;
				return 1;
			} else {
				# Oops ... it seems it's closed
				$self->{isopen} = 0;
			}
		}

		# Apparently no data is waiting to be read
		return 0;
	}

	sub getData() {
		my $self = shift;

		my $data = $self->{data};
		$self->{data} = '';
		return $data;
	}
}

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
	}

	if ( $in->readLine ) {
		$buffCon->proccessLine($in->getData());
		$termCon->output();
	}
	usleep(100);
}

$termCon->endAlternate();
