package AnyEvent::StreamXML::XMPP::Component;

use parent 'AnyEvent::StreamXML::XMPP';
use mro 'c3';
use common::sense;
use Scalar::Util 'weaken';
use uni::perl ':dumper';
use XML::Hash::LX;
use Carp;
use Digest::SHA1 'sha1_hex';

use AnyEvent::StreamXML::XMPP::NS;
use AnyEvent::StreamXML::XMPP::Iq;
use AnyEvent::StreamXML::XMPP::Presence;
use AnyEvent::StreamXML::XMPP::JID;

use Try::Tiny;
use Time::HiRes 'time';

sub feature {
	my $self   = shift;
	my $name   = shift;
	my $enable = @_ ? shift : 1;
	if ($enable) {
		$self->{disco}{ features }{ rns( $name ) }++;
	} else {
		delete $self->{disco}{ features }{ rns( $name ) };
	}
}

sub init {
	my $self = shift;
	$self->{name} or carp "It's recommended to setup a component name";
	$self->{jid} or croak "Need <jid>";
	$self->{password} or croak "Need <password>";
	$self->{stream_ns} = ns('component_accept') unless defined $self->{stream_ns};
	$self->next::method();

	$self->{disco}{ identity }{ category } ||= 'gateway';
	$self->{disco}{ identity }{ type }     ||= 'xmpp';
	$self->{disco}{ identity }{ name }     ||= $self->{name} || $self->{jid};
	$self->{disco}{ features }{ ping }++;
	$self->{disco}{ features }{ disco_info }++;
	
	weaken($self);
	$self->{stanza_handlers}{handshake} = sub {
		$self or return;
		$self->{handshaked} = 1;
		$self->event(ready => ());
	};
	$self->{stanza_handlers}{presence} = sub {
		$self or return;
		$self->event(presence => AnyEvent::StreamXML::XMPP::Presence->new($_[0],$self));
	};
	$self->{stanza_handlers}{iq} = sub {
		$self or return;
		my $node = shift;
		my $s = AnyEvent::StreamXML::XMPP::Iq->new($node, $self);
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
			my $ns = $query && $query->getAttribute('xmlns');
			#warn "iq query ($query) $ns -> ".rns($ns);
			my $event = rns($ns);
			if ( $self->handles( $event ) ) {
				# TODO: exception handler
				$self->event( $event => $s, $query );
			} else {
				warn "iq query.$ns (event $event) not handled";
				$s->error('not-acceptable', { iq => { from => $self->{jid} } });
			}
			#};warn if $@;
		}
	};
	warn dumper $self->{handlers};

	$self->on(
		stream_ready => sub {
			my ($c,$stream) = @_;
			warn "stream ready, start handshake @_";
			$self->{stream} = $stream;
			$self->{id} = $stream->getAttribute('id');
			$self->{jid} = jid($stream->getAttribute('from'));
			($self->{server}{domain}) = $self->{jid} =~ /^[^.]+\.(.+)$/;
			warn "Started on domain $self->{server}{domain}";
			$c->send({
				handshake => {
					-from => $self->{jid},
					'#text' => sha1_hex( $self->{id} . $self->{password} ),
				},
			});
		},
		disco_info => sub {
			my ($c,$iq) = @_;
			$iq->reply({
				iq => {
					query => [
						{ -xmlns => ns('disco_info') },
						{ identity => +{
							map { ("-$_" => $self->{disco}{identity}{$_}) } keys %{ $self->{disco}{identity} }
						} },
						( map { +{
							feature => { -var => ns( $_ ) }
						} } keys %{ $self->{disco}{features} } ),
					]
				}
			});
			if (! $iq->from->user) {
				unless ($self->{server}{features}) {
					$c->request({
						iq => {
							-to => $self->{server}{domain}, # Ask our server about disco
							query => { -xmlns => ns( 'disco_info' ) },
						},
					}, sub {
						if (my $iq = shift) {
							#warn "response: $iq";
							my ($query) = $iq->getElementsByTagName('query');
							my (@features) = $query->getElementsByTagName('feature');
							my $features = $self->{server}{features} ||= {};
							for ($query->getElementsByTagName('feature')) {
								$features->{ rns( $_->getAttribute('var') ) }++;
							}
							#warn dumper [ $self->{server} ];
							if ( exists $self->{server}{features}{ping} ) {
								weaken $c;
								$c or return;
								
								$c->{timers}{ping} = AE::timer 30,30,sub {
									$c or return;
									my $at = time();
									if ( $self->{ping_timeout} > 0 ) {
										$c->{timers}{ping_wait} = AE::timer $self->{ping_timeout},0,sub {
											$c or return;
											delete $c->{timers}{ping_wait};
											$self->reconnect("Ping timeout after ".sprintf("%0.4fs", time - $at))
										};
									}
									
									$c->request({
										iq => {
											-to => $self->{server}{domain}, # Ask our server about disco
											query => { -xmlns => ns( 'ping' ) },
										}
									},sub {
										warn "ping reply: in ".sprintf("%0.4fs", time - $at);
										delete $c->{timers}{ping_wait};
									});
								};
							}
						} else {
							my $time = strftime( '%b %d %H:%M:%S', localtime() );
							print STDOUT "\e[0;37m$time xx \e[0;31m!!\t\e[1;31m$_[0]\e[0m\n";
						}
						$c->event(ready => ());
					});
				}
			}
			
		},
	);
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
	$s->setAttribute( to => $iq->getAttribute('from') );
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
	$s->setAttribute( to => $iq->getAttribute('from') );
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
	};
	$self->send( $s->toString() );
	return;
}

sub request {
	my $self = shift;
	my $cb = pop;
	my $s = $self->_compose(@_);
	return $cb->(undef, "No 'to' attribute'") unless $s->getAttribute('to');
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

sub message {
	my $self = shift;
	if (ref $_[0] eq 'HASH') {
		unless ( exists $_[0]{message} ) {
			$_[0] = { message => $_[0] };
		}
	}
	my $s = $self->_compose(@_);
	my $id = $s->getAttribute('id');
	unless ($id) {
		$id = $self->nextid;
		$s->setAttribute('id',$id);
	}
	$s->setAttribute( from => $self->{jid} ) unless $s->getAttribute('from');
	$self->send( { message => $s } );
	
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
			$type eq 'available' ? () : ( -type => $type ),
			-from => $from,
			-to => $to,
			-id => $self->nextid,
		}
	});
	$self->send( $s->toString() );
	
}

1;
