package Stream;

use 5.010;
use strict;
use warnings;
use Term::ReadKey;
use Data::Dumper;
use Fcntl qw(O_NONBLOCK O_RDONLY);

sub new {
	my $class = shift;
	my $thing = shift;
	my $cbreak = shift;
	$cbreak = 0 if ! ( defined($cbreak) );

	my $self = {
	             'data' => '',
	             'file' => '',
	             'cbreak' => $cbreak,
	           };

	bless $self, $class;

	my $fd;

	if ( ref(\$thing) eq 'GLOB' ) {
		$fd = $thing;
	} else {
		$self->{file} = $thing;
		sysopen($fd, $thing, O_RDONLY|O_NONBLOCK) or die "Could not open $thing";
	}

	ReadMode ( 3, *$fd ) if ($cbreak);
	$self->{fd} = $fd;
	$self->{isopen} = 1;

	return $self;
}

sub read() {
	my $self = shift;
	my $fd = $self->{fd};
	my $d;
	my $res;

	print STDERR "Attempting read from ".$self->{file}."...\n";

	while (1) {
		$res = sysread(*$fd, $d, 1024);
		last unless (defined ($res) && $res != 0);
		print STDERR "I read ". (length $d) . " bytes\n";
		$self->{data} .= $d;
	}

	if ( ! defined ($res) && $!{EAGAIN}) {
		print STDERR "Not blocking. Waiting for data ...\n";
	} elsif (! defined ($res)) {
		print STDERR "There was an error while reading: (" . ($!+0) . ") $!\n";
	} elsif ($res == 0) {
		print STDERR "We are at eof\n";
	}
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
