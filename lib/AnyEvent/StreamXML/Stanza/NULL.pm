package AnyEvent::StreamXML::Stanza::NULL;

use overload
	'bool'   => sub { 0 },
	'""'     => sub { "" },
	'+0'     => sub { 0 },
	fallback => 1,
;

our $NULL;

sub new {
	return defined $NULL ? $NULL : $NULL = bless( \do { my $o }, $_[0] );
}

sub AUTOLOAD {
	(ref shift)->new;
}
sub DESTROY {}

1;
