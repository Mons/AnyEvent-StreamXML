package AnyEvent::StreamXML::XMPP;

use parent 'AnyEvent::StreamXML';
use mro 'c3';
use common::sense;
use uni::perl ':dumper';
use XML::Hash::LX 0.06001;
use Carp;

use Try::Tiny;
use Time::HiRes 'time';

use AnyEvent::StreamXML::XMPP::NS;
use AnyEvent::StreamXML::XMPP::Iq;
use AnyEvent::StreamXML::XMPP::Presence;
use AnyEvent::StreamXML::XMPP::Message;
use AnyEvent::StreamXML::XMPP::JID;

sub init {
	my $self = shift;
	$self->{seq} = 'aaaaa';
	$self->{jid} or croak "Need 'jid'";
	$self->{jid} = AnyEvent::StreamXML::XMPP::JID->new($self->{jid}) unless ref $self->{jid};
	$self->{stream_ns} = ns('component_accept') unless defined $self->{stream_ns};
	$self->next::method();
	$self->{stanza_handlers}{presence} = sub {
		$self or return;
		my $s = AnyEvent::StreamXML::XMPP::Presence->new($_[0],$self);
		$self->{debug_recv_stanza} and $self->{debug_recv_stanza}($s);
		$self->event(presence => $s);
	};
	$self->{stanza_handlers}{message} = sub {
		$self or return;
		my $s = AnyEvent::StreamXML::XMPP::Message->new($_[0],$self);
		$self->{debug_recv_stanza} and $self->{debug_recv_stanza}($s);
		$self->event(message => $s);
	};
	$self->{stanza_handlers}{iq} = sub {
		$self or return;
		my $node = shift;
		my $s = AnyEvent::StreamXML::XMPP::Iq->new($node, $self);
		$self->{debug_recv_stanza} and $self->{debug_recv_stanza}($s);
		my $type = $s->getAttribute('type');
		if ($type eq 'result' or $type eq 'error') {
			$s->noreply();
			# lookup by id
			my $id = $s->getAttribute('id');
			if ($id and exists $self->{req}{$id}) {
				my $cb = delete $self->{req}{$id};
				if ($type eq 'error') {
					my ($err,$etext);
					if (($err) = $s->getElementsByTagName('error') and $err = $err->firstChild) {
						$etext = $err->nodeName;
					} else {
						$etext = "Stanza type error";
					}
					$cb->(undef, $etext, $s);
				} else {
					$cb->( $s );
				}
			} else {
				warn "No callback for id $id";
			}
		}
		else {
			#warn "iq type $type";
			# request to us
			my ($query) = $s->getElementsByTagName('query');
			#eval {
			if( my $ns = $query && $query->getAttribute('xmlns') ) {
			#warn "iq query ($query) $ns -> ".rns($ns);
				my $event = rns($ns);
				if ( $self->handles( $event ) ) {
					# TODO: exception handler
					$self->event( $event => $s, $query );
				} else {
					warn "iq query.$ns (event $event) not handled";
					$s->error('not-acceptable', { iq => { -from => $self->{jid} } });
				}
			} else {
				if( my $tag = $s->firstChild ) {
					my $nn = $tag->nodeName;
					if ($nn eq 'ping') {
						if ( $self->handles( $nn ) ) {
							return $self->event( $nn => $s );
						} else {
							$s->reply();
							return;
						}
					}
					my $ns = $tag->getAttribute('xmlns');
					my $event = $ns ne $s->getAttribute('xmlns') ? rns($ns) : $tag->nodeName;
					warn "iq without query but with $tag / ".$tag->nodeName.'/xmlns='.$ns."; emitting event $event";
					if ($self->handles( $event )) {
						$self->event( $event => $s );
						return;
					}
				}
				warn "iq without query";
				$s->error('not-acceptable', { iq => { -from => $self->{jid} } });
			}
			#};warn if $@;
		}
	};
}

sub nextid {
	my $self = shift;
	return 'xm-'.$self->{seq}++;
}

sub send_start {
	my $self = shift;
	my $s = hash2xml( {
		'stream:stream' => {
			'-version'      => "1.0",
			'-xml:lang'     => "en",
			
			'-xmlns'        => $self->{stream_ns},
			'-xmlns:stream' => ns('etherx_streams'),
			'-to'           => $self->{jid},
		}
	}, doc => 1 )->documentElement->toString;
	$s =~ s{/>$}{>};
	$self->send($s);
}

sub send_end {
	my $self = shift;
	#Carp::cluck "send_end requested from @{[ (caller)[1,2] ]}";
	$self->{sent_end}++ and return;
	if( $self->{h} ) {
		$self->{h}->timeout(10);
		$self->send("</stream:stream>");
		#$self->disconnect();
	}
}

# From Component, check correctness

sub request {
	my $self = shift;
	my $cb = pop;
	my $s = $self->_compose(@_);
	#return $cb->(undef, "No 'to' attribute'") unless $s->getAttribute('to');
	my $id = $s->getAttribute('id');
	unless ($id) {
		$id = $self->nextid;
		$s->setAttribute('id',$id);
	}
	my $t;
	exists $self->{req}{$id} and warn "duplicate id $id for @{[ ( caller )[1,2] ]}\n";
	$self->{req}{$id} = sub {
		undef $t;
		$cb->( @_ );
	};
	
	$s->setAttribute( type => 'get' ) unless $s->getAttribute('type');
	$s->setAttribute( from => $self->{jid} ) unless $s->getAttribute('from');
	
	my $t; $t = AE::timer 30,0,sub {
		my $rq = delete $self->{req}{$id};
		$rq->( undef, "Response timeout" );
	};
	$self->send( $s->toString() );
}

sub reply {
	my $self = shift;
	my $iq = shift;
	if (!@_) {
		@_ = ({ iq => {} });
	}
	my $s = $self->_compose(@_);
	ref $s or die "Can't sent $_[0] as a reply to $iq at @{[ (caller)[1,2] ]}\n";
	$s->setAttribute( type => 'result' ) unless $s->getAttribute('type');
	$s->setAttribute( from => $self->{jid} );
	$s->setAttribute( to => $iq->getAttribute('from') ) if $iq->getAttribute('from');
	$s->setAttribute( id => $iq->getAttribute('id') );
	#warn "Composed reply: ".$s;
	my $rq = ($s->getElementsByTagName('query'))[0];
	if ($rq and !$rq->getAttribute('xmlns')) {
		my $q = ($iq->getElementsByTagName('query'))[0];
		if ($q) {
			$rq->setAttribute('xmlns', $q->getAttribute('xmlns'));
		} else {
			warn "iq.query doesn't have xmlns and have no iq.query in request";
		}
	}
	try { $iq->replied(1) };
	$self->send( $s->toString() );
	return;
}

our %ERR = (
	'bad-request'             => [modify => 400],
	'conflict'                => [cancel => 409],
	'feature-not-implemented' => [cancel => 501],
	'forbidden'               => [auth   => 403],
	'gone'                    => [modify => 302],
	'internal-server-error'   => [wait   => 500],
	'item-not-found'          => [cancel => 404],
	'jid-malformed'           => [modify => 400],
	'not-acceptable'          => [modify => 406],
	'not-allowed'             => [cancel => 405],
	'not-authorized'          => [auth   => 401],
	'payment-required'        => [auth   => 402],
	'recipient-unavailable'   => [wait   => 404],
	'redirect'                => [modify => 302],
	'registration-required'   => [auth   => 407],
	'remote-server-not-found' => [cancel => 404],
	'remote-server-timeout'   => [wait   => 504],
	'resource-constraint'     => [wait   => 500],
	'service-unavailable'     => [cancel => 503],
	'subscription-required'   => [auth   => 407],
	'undefined-condition'     => [cancel => 500],
	'unexpected-request'      => [wait   => 400],
);

exists $ERR{'internal-server-error'} or die "Need 'internal-server-error'";

sub error {
	my $self = shift;
	my $iq = shift;
	my $error = shift;
	exists $ERR{$error} or return warn("Unknown error: $error"),$iq->error('internal-server-error');
	if (!@_) {
		@_ = ({ iq => {} });
	}
	my $s = $self->_compose(@_);
	ref $s or die "Can't sent $_[0] as a reply to $iq at @{[ (caller)[1,2] ]}\n";
	$s->setAttribute( type => 'error' ) unless $s->getAttribute('type');
	$s->setAttribute( from => $self->{jid} );
	$s->setAttribute( to => $iq->getAttribute('from') ) if $iq->getAttribute('from');
	$s->setAttribute( id => $iq->getAttribute('id') );
	
	my $e = XML::LibXML::Element->new('error');
	$e->setAttribute( type => $ERR{$error}[ 0 ] );
	$e->setAttribute( code => $ERR{$error}[ 1 ] );
		my $n = XML::LibXML::Element->new($error);
		$n->setAttribute(xmlns => ns( 'stanzas' ));
		$e->appendChild($n);
	$s->appendChild($e);
	try {
		$iq->replied(1);
	} catch {};
	$self->send( $s->toString() );
	return;
}

sub message {
	my $self = shift;
	if (ref $_[0] eq 'HASH') {
		unless ( exists $_[0]{message} ) {
			$_[0] = { message => $_[0] };
		}
	}
	my $s = $self->_compose(@_);
	my $id = $s->getAttribute('id');
	#unless ($id) {
	#	$id = $self->nextid;
	#	$s->setAttribute('id',$id);
	#}
	$s->setAttribute( from => $self->{jid} ) unless $s->getAttribute('from');
	$self->send( $s->toString() );
	
}

sub presence {
	my $self = shift;
	my $type = shift;
	my ($from,$to) = ($self->{jid});
	if (@_ == 1) {
		$to = shift
	}
	elsif ( @_ == 2) {
		($from,$to) = @_;
	}
	else {
		warn "Wrong arguments to .presence(type, from, [to]): [$type @_]\n";
		return;
	}
	if (ref $_[0] eq 'HASH') {
		unless ( exists $_[0]{message} ) {
			$_[0] = { message => $_[0] };
		}
	}
	my $s = $self->_compose({
		presence => {
			( $type eq 'available' or ! length $type ) ? () : ( -type => $type ),
			-from => $from,
			-to => $to,
			-id => $self->nextid,
		}
	});
	$self->send( $s->toString() );
	
}

1;
