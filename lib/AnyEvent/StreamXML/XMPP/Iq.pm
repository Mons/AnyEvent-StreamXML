package AnyEvent::StreamXML::XMPP::Iq;

use parent 'AnyEvent::StreamXML::XMPP::Stanza';

sub replied { delete shift->[1];return }
*noreply = \&replied;

sub type { $_[0][2]{type} ||= $_[0][0]->getAttribute('type'); }
sub subtype {
	$_[0][2]{subtype} ||= do {eval{
		my @ch = $_[0][0]->childNodes;
		my $fc;
		for (@ch) {
			next if $_->isa('XML::LibXML::Text');
			$fc = $_;
		}
		$fc->getAttribute('xmlns');
	}};
}
sub query { $_[0][2]{query} ||= ( $_[0][0]->getElementsByTagName('query') )[0]; }

sub reply {
	my $self = shift;
	$self->[1] or return warn "No connection for reply()";
	$self->[1]->reply( $self, @_ );
	delete $self->[1];
}

sub error {
	my $self = shift;
	$self->[1] or return warn "No connection for error()";
	$self->[1]->error( $self, @_ );
	delete $self->[1];
}

sub DESTROY {
	my $self = shift;
	local $@;
	local $SIG{__DIE__} = sub { warn "Exception during StreamXML.XMPP.Iq.DESTROY: @_"; };
	$self->[1] or return @$self = ();
	$self->error('not-acceptable');
	return @$self = ();
}

1;
