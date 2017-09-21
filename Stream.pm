package Stream;

use 5.010;
use strict;
use warnings;
use IO::Select;
use Term::ReadKey;
use Data::Dumper;

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
		$fd = $thing;
	} else {
		$self->{file} = $thing;
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

sub read() {
	my $self = shift;

	my $fd = $self->{fd};
	#ReadMode ( 3, *$fd ) if ($self->{cbreak});
	while ( $self->{select}->can_read(0) ) {
		# I should be able to read ...
		my $d;
		if ( sysread(*$fd, $d, 1024) ) {
			#print STDERR "Reading " . (length $d) . " bytes ...\n";
			# I just read ...
			$self->{data} .= $d;
		} else {
			# Oops ... it seems it's closed
			last;
		}
	}

	# Apparently no data is waiting to be read
	return 1;
}

sub getData() {
	my $self = shift;

	my $data = $self->{data};
	$self->{data} = '';
	return $data;
}

sub getLines() {
	my $self = shift;
	if ( defined $self->{data} && $self->{data} =~ /\n/ ) {
		my @lines = split(/\n/,$self->{data},-1);
		$self->{data} = pop @lines;
		return \@lines;
	}
	return [];
}

1;
