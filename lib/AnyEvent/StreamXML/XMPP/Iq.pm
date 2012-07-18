package AnyEvent::StreamXML::XMPP::Iq;

use parent 'AnyEvent::StreamXML::XMPP::Stanza';

sub replied { delete shift->[2];return }
*noreply = \&replied;

sub subtype {
	return $_[0]->child(0)->attr('xmlns');
}
#sub query { $_[0]->query }

sub reply {
	my $self = shift;
	$self->[2] or return warn "No connection for reply()";
	$self->[2]->reply( $self, @_ );
	delete $self->[2];
}

sub reply_error {
	my $self = shift;
	$self->[2] or return warn "No connection for error()";
	$self->[2]->error( $self, @_ );
	delete $self->[2];
}

sub DESTROY {
	my $self = shift;
	local $@;
	local $SIG{__DIE__} = sub { warn "Exception during StreamXML.XMPP.Iq.DESTROY: @_"; };
	$self->[2] or return @$self = ();
	$self->reply_error('not-acceptable');
	return @$self = ();
}

1;
