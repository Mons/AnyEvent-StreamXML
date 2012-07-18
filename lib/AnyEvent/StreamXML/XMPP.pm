package AnyEvent::StreamXML::XMPP;

use parent 'AnyEvent::StreamXML';
use mro 'c3';
use common::sense;
use uni::perl ':dumper';
#use XML::Hash::LX 0.06001;
use XML::Fast;
use Carp;
use Scalar::Util 'weaken';

use 5.010;

use Try::Tiny;
use Time::HiRes 'time';

use AnyEvent::StreamXML::XMPP::NS;
use AnyEvent::StreamXML::XMPP::Iq;
use AnyEvent::StreamXML::XMPP::Presence;
use AnyEvent::StreamXML::XMPP::Message;
use AnyEvent::StreamXML::XMPP::JID;

sub init {
	my $self = shift;
	$self->{seq}      ||= 'aaaaa';
	$self->{jid} or croak "Need 'jid'";
	$self->{jid} = AnyEvent::StreamXML::XMPP::JID->new($self->{jid}) unless ref $self->{jid};
	$self->{stream_ns} = ns('component_accept') unless defined $self->{stream_ns};
	$self->{handlers}{StreamEnd} ||= sub {
		$self or return;
		warn "Received graceful disconnect (</stream>). Send response and reconnect...";
		#$self->send_end;
		$self->disconnect();
		$self->_reconnect_after;
	};
	$self->next::method();
	weaken($self);
	$self->{stanza_handlers}{'stream:error'} = sub {
		$self or return;
		my $s = shift;
		warn "Stream Error $s";
		my $cond = $s->child(0)->name;
		my $text = $cond . ( $s->text ? ': '.$s->text->value : '' );
		given($cond) {
			when ([qw(
				bad-format
				bad-namespace-prefix
				conflict
				connection-timeout
				improper-addressing
				internal-server-error
				invalid-from
				invalid-id
				invalid-namespace
				invalid-xml
				policy-violation
				remote-connection-failed
				resource-constraint
				restricted-xml
				system-shutdown
				unsupported-stanza-type
				xml-not-well-formed
			)]) {
				$self->reconnect($text);
			}
			when ([qw(
				host-gone
				host-unknown
				not-authorized
				unsupported-encoding
				unsupported-version
			)]) { $self->disconnect($text); };
			#when([qw(
			#	see-other-host
			#)]) {
			#	$self->disconnect($text);
				# TODO: follow
				#$self->connect;
			#};
			default {
				$self->disconnect($text);
			}
		}
		$self->disconnect(eval{ $s->child(0)->name } // "$s");
	};
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
		my $type = $s->type;
		if ($type eq 'result' or $type eq 'error') {
			$s->noreply();
			# lookup by id
			my $id = $s->id;
			$self->{h}->timeout(undef);
			if ($id and exists $self->{req}{$id}) {
				my $cb = delete $self->{req}{$id};
				if ($type eq 'error') {
					my ($err,$etext);
					if ($err = $s->error->child(0) ) {
						$etext = $err->name;
					} else {
						$etext = "Stanza type error";
					}
					$cb->(undef, $etext, $s);
				} else {
					$cb->( $s );
				}
			} else {
				#warn "No callback for id $id: $s ";
			}
		}
		else {
			#warn "iq type $type";
			# request to us
			my $query = $s->query;
			#eval {
			if( my $ns = $query->attr('xmlns') ) {
			#warn "iq query ($query) $ns -> ".rns($ns);
				my $event = rns($ns);
				if ( $self->handles( $event ) ) {
					# TODO: exception handler
					$self->event( $event => $s, $query );
				} else {
					if ($ns eq ns('version')) {
						$s->reply({iq => {
							query => {
								-xmlns => $ns,
								name => 'AnyEvent::StreamXML',
								version => $AnyEvent::StreamXML::VERSION,
							},
						}});
					} else {
						warn "iq query.$ns (event $event) not handled";
						$s->reply_error('not-acceptable', { iq => { -from => $self->{jid} } });
					}
				}
			} else {
				if( my $tag = $s->child(0) ) {
					my $nn = $tag->name;
					if ($nn eq 'ping') {
						if ( $self->handles( $nn ) ) {
							return $self->event( $nn => $s );
						} else {
							$s->reply();
							return;
						}
					}
					elsif ($nn eq 'time') {
						if ( $self->handles( $nn ) ) {
							return $self->event( $nn => $s );
						} else {
							use POSIX 'strftime';
							my $off = strftime("%z",gmtime(time));
							$off =~ s{(?=\d{2}$)}{:};
							$s->reply({iq => {
								time => {
									-xmlns => ns('time'),
									tzo => $off,
									utc => strftime('%Y-%m-%dT%H:%M:%SZ',gmtime()),
								},
							}});
							return;
						}
					}
					my $ns = $tag->attr('xmlns');
					my $event = $ns ne $s->attr('xmlns') ? rns($ns) : $tag->name;
					#warn "iq without query but with $tag / ".$tag->nodeName.'/xmlns='.$ns."; emitting event $event";
					if ($self->handles( $event )) {
						$self->event( $event => $s );
						return;
					} else {
						warn "Not handled $event";
					}
				}
				$s->reply_error('not-acceptable', { iq => { -from => $self->{jid} } });
			}
			#};warn if $@;
		}
	};
}

sub nextid {
	my $self = shift;
	return ($self->{seq_pref} || 'xm').'-'.$self->{seq}++;
}

sub send_start {
	my $self = shift;
	my $s = hash2xml({
		'stream:stream' => {
			'-version'      => "1.0",
			'-xml:lang'     => "en",
			
			'-xmlns'        => $self->{stream_ns},
			'-xmlns:stream' => ns('etherx_streams'),
			'-to'           => $self->{jid},
		}
	});
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
	my $cb;$cb = pop if ref $_[-1] eq 'CODE';
	my $s = $self->_compose(@_);
	#return $cb->(undef, "No 'to' attribute'") unless $s->getAttribute('to');
	#warn "composed: ".dumper $s;
	my $id = $s->attr('id');
	unless ($id) {
		$id = $self->nextid;
		$s->attr('id',$id);
	}
	$s->attr( type => 'get' ) unless $s->attr('type');
	$s->attr( from => $self->{jid} ) unless $s->attr('from');
	if ($cb) {
		my $t;
		exists $self->{req}{$id} and warn "duplicate id $id for @{[ ( caller )[1,2] ]}\n";
		$self->{req}{$id} = sub {
			undef $t;
			$cb->( @_ );
		};
		
		my $t; $t = AE::timer 30,0,sub {
			my $rq = delete $self->{req}{$id};
			$rq->( undef, "Response timeout" );
		};
	}
	$self->{h}->timeout($self->{timeout}) if $cb;
	$self->send( $s->toString() );
	return $id;
}

sub reply {
	my $self = shift;
	my $iq = shift;
	if (!@_) {
		@_ = ({ iq => {} });
	}
	my $r = $_[0]{iq};
	my $s = $self->_compose(@_);
	ref $s or die "Can't sent $_[0] as a reply to $iq at @{[ (caller)[1,2] ]}\n";
	$s->attr('type', 'result') unless $s->attr('type');
	$s->attr('from', $iq->attr('to') // $self->{jid}) unless length $s->attr('from');
	$s->attr('to', $iq->attr('from')) if $iq->attr('from');
	$s->attr('id', $iq->id);
	#warn "reply: $s";
	#warn "Composed reply: ".$s;
	my $rq = $s->child(0);
	if ($rq and !$rq->attr('xmlns') and $rq->name ne 'error') {
		if (my $ns = $iq->child(0)->attr('xmlns')) {
			$rq->attr('xmlns', $ns);
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
	my $self  = shift;
	my $iq    = shift;
	my $error = shift;
	my $errtext;
	if (ref $error) {
		($error,$errtext) = @$error;
	}
	exists $ERR{$error} or return warn("Unknown error: $error"),$iq->reply_error('internal-server-error');
	if (!@_) {
		@_ = ({ iq => {} });
	}
	my $s = $self->_compose(@_);
	ref $s or die "Can't sent $_[0] as a reply to $iq at @{[ (caller)[1,2] ]}\n";
	$s->attr('type', 'error') unless $s->attr('type');
	$s->attr('from', $self->{jid});
	$s->attr('to', $iq->attr('from')) if $iq->attr('from');
	$s->attr('id', $iq->id);
	$s->child({
		error => {
			-type  => $ERR{$error}[ 0 ],
			-code  => $ERR{$error}[ 1 ],
			$error => { -xmlns => ns('stanzas') },
			$errtext ? (
				text => {
					-xmlns => 'urn:ietf:params:xml:ns:xmpp-stanzas',
					'#text' => $errtext,
				},
			) : (),
		}
	});
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
	my $id = $s->id;
	unless ($id) {
		$id = $self->nextid;
		$s->id($id);
	}
	$s->attr( from => $self->{jid} ) unless $s->attr('from');
	$self->send( $s->toString() );
	
}

sub presence {
	my $self = shift;
	my $type = shift;
	my $data = ref $_[-1] eq 'HASH' ? pop : {};
	my ($from,$to) = ($self->{jid});
	if (@_ == 1) {
		$to = shift
	}
	elsif ( @_ == 2) {
		($from,$to) = @_;
	}
	else {
		warn "Wrong arguments to .presence(type, from, [to], [{data}]): ".dumper([$type,@_])." at @{[ (caller)[1,2] ]}\n";
		return;
	}
	my $s = $self->_compose({
		presence => {
			( $type eq 'available' or ! length $type ) ? () : ( -type => $type ),
			-from => $from,
			-to => $to,
			-id => $self->nextid,
			%$data,
		}
	});
	$self->send( $s->toString() );
	
}

1;
