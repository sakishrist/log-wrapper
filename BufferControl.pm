package BufferControl;

use 5.010;
use strict;
use warnings;
use IO::Select;

sub new ($$) {
	my $class = shift;
	my $agReg = shift;
	my $filesReg = shift;
	my $omit = shift;

	my $self = {
							 'buff' => [],
							 'count' => 0,
							 'skipped' => 0,
							 'aggregated' => 0,
							 'changed' => 0,
							 'updatesStart' => undef,
							 'curFile' => '',
							 'lastPosIndex' => {},
							 'reg' => {},
							 'agReg' => $agReg,
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

sub compileRegs () {
	my $self = shift;

	my $reg = $self->{reg};
	my $agReg = $self->{agReg};
	my $filesReg = $self->{filesReg};

	foreach my $rfg (keys %{$filesReg}) {
		my $files_str;
		foreach my $f (  @{ $filesReg->{$rfg} }  ) {
			$files_str .= (defined $files_str ? '|' : '') . $f;
		}
		$reg->{$rfg} = { 'files' => qr/($files_str)/, 'aggRegs' => {} };
	}

	foreach my $rg (keys %{$agReg}) {
		my $reg_str;
		foreach my $r (  @{ $agReg->{$rg}->{regs} }  ) {
			$reg_str .= (defined $reg_str ? '|' : '') . $r;
		}
		$reg->{ $agReg->{$rg}->{files} }->{aggRegs}->{$rg} = qr/($reg_str)/;
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

	foreach my $rfg (keys %{$reg}) {
		if ( $file =~ $reg->{$rfg}->{files} ) {
			return $rfg;
		}
	}
}

sub matchGroup ($$) {
	my $self = shift;
	my $line = shift;
	my $file = shift;

	my $filesMatch;
	if (! ( $filesMatch = $self->matchFile($file) )) {
		return;
	}

	my $regGroups = $self->{reg}->{$filesMatch}->{aggRegs};

	foreach my $rg (keys %{$regGroups}) {
		if ( $line =~ $regGroups->{$rg} ) {
			return $rg;
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

	$self->{changed} = 1;

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

			$$updatesStart = $$posIndex;
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

1;
