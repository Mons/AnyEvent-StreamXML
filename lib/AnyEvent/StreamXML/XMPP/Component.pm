package AnyEvent::StreamXML::XMPP::Component;

use parent 'AnyEvent::StreamXML::XMPP';
use mro 'c3';
use common::sense;
use Scalar::Util 'weaken';
use uni::perl ':dumper';
use XML::Hash::LX;
use Carp;
use Digest::SHA1 'sha1_hex';
use POSIX 'strftime';

use AnyEvent::StreamXML::XMPP::NS;
use AnyEvent::StreamXML::XMPP::Iq;
use AnyEvent::StreamXML::XMPP::Presence;
use AnyEvent::StreamXML::XMPP::Message;
use AnyEvent::StreamXML::XMPP::JID;

use Try::Tiny;
use Time::HiRes 'time';

sub domain { shift->{jid} }
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
	$self->next::method(@_);
	$self->{seq_pref} ||= 'cm';
	$self->{name} or carp "It's recommended to setup a component name";
	$self->{jid} or croak "Need <jid>";
	$self->{password} or croak "Need <password>";
	$self->{stream_ns} = ns('component_accept') unless defined $self->{stream_ns};
	$self->{port} ||= 5275;
	$self->{use_ping} = 1 unless defined $self->{use_ping};

	$self->{disco}{ identity }{ category } ||= 'gateway';
	$self->{disco}{ identity }{ type }     ||= 'xmpp';
	$self->{disco}{ identity }{ name }     ||= $self->{name} || $self->{jid};
	$self->{disco}{ features }{ ping }++;
	$self->{disco}{ features }{ disco_info }++;
	
	weaken($self);
	$self->{stanza_handlers}{'stream:error'} = sub {
		$self or return;
		warn "Stream Error @_";
	};
	$self->{stanza_handlers}{handshake} = sub {
		$self or return;
		$self->{handshaked} = 1;
		$self->event(handshaked => ());
	};
	$self->{stanza_handlers}{presence} = sub {
		$self or return;
		$self->event(presence => AnyEvent::StreamXML::XMPP::Presence->new($_[0],$self));
	} if 0;
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
			if( my $ns = $query && $query->getAttribute('xmlns') ) {
			#warn "iq query ($query) $ns -> ".rns($ns);
				my $event = rns($ns);
				if ( $self->handles( $event ) ) {
					# TODO: exception handler
					$self->event( $event => $s, $query );
				} else {
					warn "iq query.$ns (event $event) not handled";
					$s->error('not-acceptable', { iq => { from => $self->{jid} } });
				}
			} else {
				warn "iq without query";
				$s->error('not-acceptable', { iq => { from => $self->{jid} } });
			}
			#};warn if $@;
		}
	} if 0;
	$self->{stanza_handlers}{message} = sub {
		$self or return;
		$self->event(message => AnyEvent::StreamXML::XMPP::Message->new($_[0],$self));
	} if 0;
	$self->{handlers}{StreamEnd} ||= sub {
		$self or return;
		warn "Received graceful disconnect (</stream>). Send response and reconnect...";
		#$self->send_end;
		$self->disconnect();
		$self->_reconnect_after;
	};
	#warn dumper $self->{handlers};

	$self->on(
		stream_ready => sub {
			my ($c,$stream) = @_;
			#warn "stream ready, start handshake @_";
			# TODO: domain detection
			$self->{stream} = $stream;
			$self->{id} = $stream->getAttribute('id');
			if (( !$self->{jid} or $self->{jid} !~ /\./) and $stream->getAttribute('from') ) {
				$self->{jid} = jid($stream->getAttribute('from'));
			}
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
							$self->cleanup(sub{ delete $self->{server} });
							my ($query) = $iq->getElementsByTagName('query');
							my (@features) = $query->getElementsByTagName('feature');
							my $features = $self->{server}{features} ||= {};
							for ($query->getElementsByTagName('feature')) {
								$features->{ rns( $_->getAttribute('var') ) }++;
							}
							#warn dumper [ $self->{server} ];
							if ( exists $self->{server}{features}{ping} and $self->{use_ping} ) {
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
										#warn "ping reply: in ".sprintf("%0.4fs", time - $at);
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
		register => sub {
			my ($c,$iq) = @_;
			my $type = $iq->type;
			if ($type eq 'set') {
				if (my $rem = $iq->getElementsByTagName('remove')) {
					$type = "remove";
				}
			}
			$c->event("register_$type",$iq);
		},
	);
}


1;
