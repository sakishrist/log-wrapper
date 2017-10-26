package BufferControl;

use 5.010;
use strict;
use warnings;
use IO::Select;
use Data::Dumper;

# buff [ Text, Aggregations, Filename, Rule match, Cols, Meta ]

sub new ($$) {
	my $class = shift;
	my ($agRegs, $colRegs, $filesReg, $omit) = @_;

	my $self = {
							 'buff' => [],
							 'count' => 0,
							 'skipped' => 0,
							 'aggregated' => 0,
							 'changed' => 1,
							 'updatesStart' => undef,
							 'curFile' => '',
							 'lastPosIndex' => {},
							 'reg' => {},
							 'agRegs' => $agRegs,
							 'colRegs' => $colRegs,
							 'filesReg' => $filesReg,
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

sub buildReg () {
	my $self = shift;
	my $regs = shift;

	my $str;

	foreach my $r (  @{ $regs }  ) {
		$str .= (defined $str ? '|' : '') . $r;
	}
	return qr/($str)/;
}

sub compileRegs () {
	my $self = shift;

	my $reg = $self->{reg};
	my $agRegs = $self->{agRegs};
	my $colRegs = $self->{colRegs};
	my $filesReg = $self->{filesReg};

	foreach my $frg (keys %{$filesReg}) {
		$reg->{$frg} = { 'files' => $self->buildReg($filesReg->{$frg}), 'aggRegs' => {}, 'colRegs' => {} };
	}

	foreach my $arg (keys %{$agRegs}) {
		$reg->{ $agRegs->{$arg}->{files} }->{aggRegs}->{$arg} = $self->buildReg($agRegs->{$arg}->{regs});
	}

	foreach my $crg (keys %{$colRegs}) {
		$reg->{ $colRegs->{$crg}->{files} }->{colRegs}->{$crg} = {
			'reg' => $self->buildReg($colRegs->{$crg}->{regs}),
			'col' => $colRegs->{$crg}->{color}
		}
	}
}

sub updateIndices () {
	my $self = shift;

	my $buff = $self->{buff};
	my $updatesStart = \$self->{updatesStart};
	my $lastPosIndex = $self->{lastPosIndex};

	for ( my $linenum=$updatesStart; $linenum <= (scalar @{$buff})-1; $linenum++ ) {
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
	my @files;

	foreach my $frg (sort keys %{$reg}) {
		if ( $file =~ $reg->{$frg}->{files} ) {
			push @files, $frg;
		}
	}

	return @files;
}

sub matchAggGroup ($$) {
	my $self = shift;
	my $line = shift;
	my $file = shift;

	my ($filesMatch) = $self->matchFile($file);

	return if (! defined $filesMatch);

	my $regGroups = $self->{reg}->{$filesMatch}->{aggRegs};
	foreach my $arg (sort keys %{$regGroups}) {
		if ( $line =~ $regGroups->{$arg} ) {
			return $arg;
		}
	}
}

sub getCols ($$) {
	my $self = shift;
	my $line = shift;
	my $file = shift;

	my @filesMatch = $self->matchFile($file);
	#print STDERR Dumper(@filesMatch);
	#exit;
	my @positions = ();

	foreach my $f (@filesMatch) {
		my $colGroups = $self->{reg}->{$f}->{colRegs};

		foreach my $crg (sort keys %{$colGroups}) {
			if ( $line =~ $colGroups->{$crg}->{reg} ) {

				for (my $i = 2; $i<(scalar @-); $i++) {
					push @positions, [ $-[$i], $colGroups->{$crg}->{col} ] ;
					push @positions, [ $+[$i], -1 ] ;
				}
			}
		}
	}

	my $sorted;
	@$sorted = sort { $b->[0] <=> $a->[0] or $b->[1] <=> $a->[1] } @positions;

	my @colStack = ();
	for (my $i = (scalar @$sorted) - 1; $i >= 0; $i--) {
		if ($sorted->[$i]->[1] < 0) {
			if (scalar @colStack && pop @colStack && scalar @colStack) {
				$sorted->[$i]->[1] = $colStack[-1];
			}
		} else {
			push @colStack, $sorted->[$i]->[1];
		}
	}

	return $sorted;
}

sub addLine ($) {
	my $self = shift;
	my $line = shift;
	my $curFile = shift;
	my $isMeta = shift;
	$isMeta = 0 unless defined $isMeta;

	my $buff = $self->{buff};
	my $count = \$self->{count};
	my $updatesStart = \$self->{updatesStart};
	my $aggregated = \$self->{aggregated};
	my $posIndex = \$self->{lastPosIndex}->{$curFile};
	#my $skipped = \$self->{skipped};

	$$count++;

	my $match;
	my $prevMatch;

	unless ($isMeta) {
		$match = $self->matchAggGroup($line, $curFile);
		$prevMatch = $buff->[$$posIndex][3] if (defined $$posIndex && defined $buff->[$$posIndex][3]);
	}

	# IF THE LINE MATCHES SOME RULE AND ...
	# IF THE LINE BEFORE THIS ONE WAS MATCHED WITH THE SAME RULE ...
	my $toUpdate = ($match && $prevMatch && $match eq $prevMatch);

	if ($toUpdate) {
		$$aggregated++;

		$$updatesStart = $$posIndex;
		push(@{$buff}, splice(@{$buff}, $$posIndex, 1));
		$$posIndex = (scalar @{$buff})-1;

		$self->updateIndices();

		$buff->[(scalar @{$buff})-1][0] = $line;
		$buff->[(scalar @{$buff})-1][1]++;
		$buff->[(scalar @{$buff})-1][4] = $self->getCols($line, $curFile);
	} else {
		push(@{$buff}, [$line, 0, $curFile, $match, $self->getCols($line, $curFile), $isMeta]);
		$$posIndex = (scalar @{$buff})-1;
	}
}

sub removeTabs () {
	my $self = shift;
	my $line = $self->{buff}->[(scalar @{$self->{buff}})-1];

	my $withoutTabs = '';
	my $lastT;
	foreach my $t (split(/\t/,$line->[0])) {
		if (defined $lastT) {
			$lastT =~ s/\e\[.*?m//g;

			my $len = (8 - (length $lastT) % 8);
			$withoutTabs .= (" " x $len) if (defined $lastT);
		}
		$withoutTabs .= $t;
		$lastT = $t;
	}
	$line->[0] = $withoutTabs;
}

sub proccessLines ($) {
	my $self = shift;
	my $lines = shift;
	my $curFile = shift;

	foreach my $line (@$lines) {
		chomp ($line);

		$self->{changed} = 1;
		$self->addLine($line, $curFile);
		$self->removeTabs();
	}
}

sub addSeparator () {
	my $self = shift;

	my $buff = $self->{buff};

	$self->addLine("", "", 1);
}

1;
