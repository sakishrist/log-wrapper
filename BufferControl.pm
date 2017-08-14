package BufferControl;

use 5.010;
use strict;
use warnings;
use IO::Select;

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

	foreach my $frg (keys %{$reg}) {
		if ( $file =~ $reg->{$frg}->{files} ) {
			return $frg;
		}
	}
}

sub matchAggGroup ($$) {
	my $self = shift;
	my $line = shift;
	my $file = shift;

	my $filesMatch;
	if (! ( $filesMatch = $self->matchFile($file) )) {
		return;
	}

	my $regGroups = $self->{reg}->{$filesMatch}->{aggRegs};

	foreach my $arg (keys %{$regGroups}) {
		if ( $line =~ $regGroups->{$arg} ) {
			return $arg;
		}
	}
}

sub proccessLine ($) {
	my $self = shift;
	my $line = shift;

	my $curFile = \$self->{curFile};
	my $buff = $self->{buff};
	my $count = \$self->{count};
	my $updatesStart = \$self->{updatesStart};
	my $skipped = \$self->{skipped};
	my $aggregated = \$self->{aggregated};
	my $posIndex = \$self->{lastPosIndex}->{$$curFile};

	chomp( $line );

	# IGNORE EMPTY LINES
	return if ($line =~ '^$');


	# MATCH TAIL FILENAME LINES
	if (my $f = $self->matchTailFilename($line)) {
		$$curFile = $f;
	} else {
		$self->{changed} = 1;
		$$count++;

		my $match = $self->matchAggGroup($line, $$curFile);
		my $prevMatch = $buff->[$$posIndex][3] if (defined $$posIndex && defined $buff->[$$posIndex][3]);

		# IF THE LINE MATCHES SOME RULE AND ...
		# IF THE LINE BEFORE THIS ONE WAS MATCHED WITH THE SAME RULE ...
		my $toUpdate = ($match && $prevMatch && $match eq $prevMatch);

		if ($toUpdate) {
			$$aggregated++;

			$$updatesStart = $$posIndex;
			push(@{$buff}, splice(@{$buff}, $$posIndex, 1));
			$$posIndex = (scalar @{$buff})-1;

			$self->updateIndices();

			$buff->[(scalar @{$buff})-1][0]=$line;
			$buff->[(scalar @{$buff})-1][1]++;
		} else {
			push(@{$buff}, [$line, 0, $$curFile, $match]);
			$$posIndex = (scalar @{$buff})-1;
		}
	}
}

sub addSeparator () {
	my $self = shift;

	my $buff = $self->{buff};

	push(@{$buff}, ["", 0, ""]);
}

1;
