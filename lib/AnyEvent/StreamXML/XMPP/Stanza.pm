package AnyEvent::StreamXML::XMPP::Stanza;

use uni::perl;
use Scalar::Util 'weaken';
use AnyEvent::StreamXML::XMPP::JID 'jid';
use parent 'AnyEvent::StreamXML::Stanza';
use Clone ();

use overload
	'""'   => sub { $_[0]->toString() },
	'bool' => sub { 1 },
	'0+'   => sub { Scalar::Util::refaddr($_[0]) },
	fallback => 1,
;

# 0 - name
# 1 - struct
# 2 - conn


sub new {
	my $class = shift;
	my $node = shift;
	my $conn = shift;
	bless $node, $class;
	weaken( $node->[2] = $conn );
	return $node;
}

sub id      { shift->attr('id', @_) }
sub from    { jid( shift->attr('from', @_) ) }
sub to      { jid( shift->attr('to', @_) ) }
sub type    { shift->attr('type', @_) }

sub clone {
	my $self = shift;
	my $reverse = shift;
	my $node = AnyEvent::StreamXML::Stanza->newn( $self->[0], Clone::clone( $self->[1] ) );
	
	if ($reverse) {
		$node->attr('from', $self->to );
		$node->attr('to',   $self->from );
	}
	return ref($self)->new( $node, $self->[2] );
}

sub DESTROY {
	my $self = shift;
	@$self = ();
}

1;
