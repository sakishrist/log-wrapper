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
							 'changed' => 0,
							 'updatesStart' => undef,
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
