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

sub read() {
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

1;
