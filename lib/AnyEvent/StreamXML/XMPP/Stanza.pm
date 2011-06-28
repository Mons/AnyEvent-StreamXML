package AnyEvent::StreamXML::XMPP::Stanza;

use uni::perl;
use Scalar::Util 'weaken';
use AnyEvent::StreamXML::XMPP::JID 'jid';

use overload
	'""'   => sub { $_[0][0]->toString() },
	'bool' => sub { 1 },
	'0+'   => sub { Scalar::Util::refaddr($_[0]) },
	fallback => 1,
;
sub new {
	my $class = shift;
	my $node = shift;
	my $conn = shift;
	my $self = bless [$node,$conn],$class;
	weaken($self->[1]);
	return $self;
}

sub from { $_[0][2]{from} ||= jid( $_[0][0]->getAttribute('from') ); }
sub to   { $_[0][2]{to}   ||= jid( $_[0][0]->getAttribute('to') ); }

our $AUTOLOAD;
sub  AUTOLOAD {
	no strict 'refs';
	my ($name) = $AUTOLOAD =~ /(?:^|:)([^:]+)$/;
	*$name = sub {
		shift->[0]->$name(@_);
	};
	goto &$name;
	#$self->[0]->$name(@_);
}

sub DESTROY {
	my $self = shift;
	@$self = ();
}

1;
