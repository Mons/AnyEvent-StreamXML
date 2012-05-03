package AnyEvent::StreamXML::XMPP::Server::Conn;

use uni::perl;
use Scalar::Util 'weaken';
use mro 'c3';
use parent 'AnyEvent::StreamXML::XMPP';

use XML::Hash::LX;

use AnyEvent::StreamXML::XMPP::NS;
use AnyEvent::StreamXML::XMPP::Iq;
use AnyEvent::StreamXML::XMPP::Presence;
use AnyEvent::StreamXML::XMPP::Message;
use AnyEvent::StreamXML::XMPP::JID;

sub _reconnect_after {
	weaken( my $self = shift );
	warn "reconnect after @_";
	$self->{end} and $self->{end}();
	return;
}

sub nextid {
	my $self = shift;
	return 'srv-'.$self->{seq}++;
}

sub init {
	my $self = shift;
	$self->{jid} = 'rambler.ru';
	$self->{stream_ns} or croak "Define stream_ns";
	$self->next::method(@_);
	#$self->{seq} = 'aaaaa';
	
	$self->{disco}{ features }{ ping }++;
	
	#warn "Creating stream $self->{id}";
	weaken $self;
	$self->on(
		stream_ready => sub {
			shift;
			$self->initial_stream(@_);
		},
		ping => sub {
			shift;
			shift->reply;
		},
	);
	$self->on(
		disco_info => sub {
			# <iq type="result" id="ae-aaaaa" from="rambler.ru" to="roster-test.rambler.ru">
			#   <query xmlns="http://jabber.org/protocol/disco#info">
			#     <feature var="..."/>
			my ($c,$iq) = @_;
			$iq->reply({
				iq => {
					query => [
						{ -xmlns => ns('disco_info') },
						( map { +{
							feature => { -var => ns( $_ ) }
						} } keys %{ $self->{disco}{features} } ),
					]
				}
			});
		},
	);

	#$self->_on_connected_success($self->{fh});
	$self->_connected($self->{fh});
}

sub send_start {}

sub stream_info {
	my $self = shift;
	my $s    = shift;
	# TODO:
	# extract jid and peer from initial stream
	die ("Reimplement in subclasses");
}

sub initial_stream {
	my $self = shift;
	my $s    = shift;
	$self->stream_info($s);
	# ou <<   <stream:stream xmlns:stream="http://etherx.jabber.org/streams" xmlns="jabber:component:accept" xml:lang="en" version="1.0" to="roster-test.rambler.ru">
	# in >>   <stream:stream xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:component:accept' from='roster-test.rambler.ru' id='a82MG53oA3'>
	
	my $s = hash2xml( {
		'stream:stream' => {
			'-version'      => "1.0",
			'-xml:lang'     => "en",
			
			'-xmlns'        => $self->{stream_ns},
			'-xmlns:stream' => ns('etherx_streams'),
			$self->{jid} ? ( '-from' => $self->{jid}  ) : (),
			$self->{peer} ? ( '-to'  => $self->{peer} ) : (),
			'-id'           => $self->{id},
		}
	}, doc => 1 )->documentElement->toString;
	$s =~ s{/>$}{>};
	$self->send($s);
}

sub setup_handlers {
	weaken( my $self = shift );
	$self->{setup} and $self->{setup}($self);
	return;
}

package AnyEvent::StreamXML::XMPP::Server::Conn::Component;

use Scalar::Util 'weaken';
use mro 'c3';
use parent -norequire => 'AnyEvent::StreamXML::XMPP::Server::Conn';

use XML::Hash::LX;
use AnyEvent::StreamXML::XMPP::NS;
use AnyEvent::StreamXML::XMPP::Iq;
use AnyEvent::StreamXML::XMPP::Presence;
use AnyEvent::StreamXML::XMPP::Message;
use AnyEvent::StreamXML::XMPP::JID;

sub nextid {
	my $self = shift;
	return 'srv-cm-'.$self->{seq}++;
}

sub stream_info {
	my $self = shift;
	my $s    = shift;
	# extract jid and peer from initial stream
	my $jid = $s->getAttribute("to");
	$self->{peer} = jid($jid);
}

sub init {
	my $self = shift;
	$self->{stream_ns} = ns('component_accept');
	
	$self->next::method(@_);
	$self->{send_color} = '1;35';
	$self->{recv_color} = '1;36';
	
	$self->{stanza_handlers}{handshake} = sub {
		$self or return;
		# accept handshake
		$self->send({
			handshake => '',
		});
		# <iq type="get" id="420-701" from="component.rambler.ru" to="roster-test.rambler.ru"><query xmlns="http://jabber.org/protocol/disco#info"/></iq>
		# send disco
		#warn "Sending disco to $self->{peer}";
		$self->request({
			iq => {
				-type  => 'get',
				#-from  => 'component.rambler.ru',
				-to    => $self->{peer},
				query => {
					-xmlns => ns('disco_info'),
				},
			},
		}, sub {
			my $iq = shift;
			#warn "Received disco_info reply";
			#$self->{jid} = 'rambler.ru';
		});
		
		use Time::HiRes 'time';
		my $counter = 0;my $start = time;
		my $active;
		$| = 1;
		$self->setup_handlers();
		return;
		my $rr;$rr = sub {
			$active++;
			return if $active > 20;
			$self->request({
				iq => {
					-type  => 'get',
					-from  => 'mons@rambler.ru',
					-to    => $self->{peer},
					query => {
						-xmlns => ns('register'),
					},
				},
			}, sub {
				my $iq = shift;
				$active--;
				#warn "Received register reply";
				$counter ++;
				if ($counter %100 == 0) {
					printf "\r%0.2f/s     ", $counter / (time - $start);
				}
				$rr->();
				#$self->{jid} = 'rambler.ru';
			});
		};$rr->() for 1..20;

	};
}

package AnyEvent::StreamXML::XMPP::Server::Conn::Client;

use uni::perl ':dumper';
use Scalar::Util 'weaken';
use mro 'c3';
use parent -norequire => 'AnyEvent::StreamXML::XMPP::Server::Conn';

use XML::Hash::LX;
use AnyEvent::StreamXML::XMPP::NS;
use AnyEvent::StreamXML::XMPP::Iq;
use AnyEvent::StreamXML::XMPP::Presence;
use AnyEvent::StreamXML::XMPP::Message;
use AnyEvent::StreamXML::XMPP::JID;
use MIME::Base64 qw(encode_base64 decode_base64);


sub ACCEPTED ()  { 0 }
sub AUTHORIZED () { 1 }

sub CONNECTED ()  { 2 }

sub nextid {
	my $self = shift;
	return 'srv-cl-'.$self->{seq}++;
}


sub auth_failure {
	my $self = shift;
	my $type = shift;
					# encryption-required
					# aborted
					# incorrect-encoding
					# invalid-mechanism
					# malformed-request
					# mechanism-too-weak
					# not-authorized
					# invalid-mechanism
	$self->send({
		failure => {
			-xmlns => 'urn:ietf:params:xml:ns:xmpp-sasl',
			$type => '',
		}
	});
}

sub auth_success {
	my $self = shift;
	$self->send({
		success => {
			-xmlns => 'urn:ietf:params:xml:ns:xmpp-sasl',
		}
	});
	# Now awaiting for stream restart
	$self->{state} = AUTHORIZED;
	$self->_make_parser;
}

=for rem

connected
<stream:>
<starttls>
[+ssl]

connected
<stream:>
<auth><success>

authorized
<stream:>


<bind>
connected resource

<roster>
interested res

<presence>
available

=cut

sub stream_info {
	my $self = shift;
	my $s    = shift;
	# extract jid and peer from initial stream
	if( my $jid = $s->getAttribute("from") ) {
		$self->{peer} = jid($jid);
	}
	if( my $jid = $s->getAttribute("to") ) {
		$self->{jid} = jid($jid);
	}
}

sub init {
	my $self = shift;
	$self->{stream_ns} = ns('client');
	$self->next::method(@_);
	$self->{state} = ACCEPTED;
	
	$self->{auth_handlers}{PLAIN} = sub {
		my $s = shift;
		my $text = $s->textContent;
		my $data = decode_base64($text);
		if( my ($l,$p) = $data =~ /^\0(.+)\0(.+)$/s ) {
			#warn dumper [ $l,$p ];
			$self->{login} = $l =~ /\@/ ? lc($l) : $l.'@'.$self->{jid};
			$self->{peer} = jid($self->{login});
			$self->auth_success();
		} else {
			$self->auth_failure('malformed-request');
		}
	};
}

sub initial_stream {
	my $self = shift;
	$self->next::method(@_);
	#<stream:features><rsid xmlns="jabber:iq:rsid"/><starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>
	#	<mechanisms xmlns="urn:ietf:params:xml:ns:xmpp-sasl"><mechanism>PLAIN</mechanism><required/></mechanisms><auth xmlns='http://jabber.org/features/iq-auth'/></stream:features>
	
	given ($self->{state}) {
		when (ACCEPTED) {
			$self->send({
				'stream:features' => {
					mechanisms => {
						-xmlns => 'urn:ietf:params:xml:ns:xmpp-sasl',
						required => '',
						mechanism => [
							'PLAIN',
						],
					}
				},
			});
			# starttls...
			$self->{stanza_handlers}{auth} = sub {
				my $s = shift;
				my $mech = uc $s->getAttribute('mechanism');
				#warn "auth $mech @_";
				if (exists $self->{auth_handlers}{$mech}) {
					$self->{auth_handlers}{$mech}($s);
				} else {
					$self->auth_failure('invalid-mechanism');
				}
			};
		}
		when (AUTHORIZED) {
			$self->send({
				'stream:features' => {
					bind   => { -xmlns => 'urn:ietf:params:xml:ns:xmpp-bind', required => '' },
					sesson => { -xmlns => 'urn:ietf:params:xml:ns:xmpp-session', optional => '' },
				},
			});
			$self->{_}{wait_bind} = $self->on('bind' => sub {
				my $self = shift;
				my $b = shift;
				my ($resn) = $b->getElementsByTagName('resource');
				my $res = $resn && $resn->textContent || '';
				if ( length $res and exists $self->{check_res} and $self->{check_res}->( $self->{login}, $res ) ) {
					# ok
				}
				elsif (exists $self->{gen_res}) {
					$res = $self->{gen_res}->( $self->{login} );
				} else {
					$b->error('not-allowed');
					return;
				}
				
					#warn "bind $res";
					$self->{res} = $res;
					$self->{peer} = 
					$self->{full} = jid( $self->{login}.'/'.$res );
					$b->reply({
						iq => {
							bind => {
								-xmlns => 'urn:ietf:params:xml:ns:xmpp-bind',
								jid => "$self->{full}",
							}
						}
					});
					$self->{state} = CONNECTED;
					delete $self->{_}{wait_bind};
					$self->setup_handlers();
			});
			$self->{_}{wait_session} = $self->on('session' => sub {
				my $self = shift;
				shift->reply();
				delete $self->{_}{wait_session};
			});
		}
		default {
			warn "open stream in wrong state";
		}
	}
	
}


package AnyEvent::StreamXML::XMPP::Server::CM;

use 5.008008;
use common::sense 2;m{
use strict;
use warnings;
};
use Carp;

sub new {
	my $pk = shift;
	my $self = bless {
		id  => {  }, # id to obj
		jid => {  }, # jid to obj
	},$pk;
}

sub assign {
	my $self = shift;
	my ($id,$jid,$c) = @_;
	$self->{id}{$id} = $self->{jid}{ $jid->bare }{ $jid->res } = $c;
	#{
	#	id  => $id,
	#	jid => $jid,
	#	c   => $c,
	#}
}

sub free_id {
	my $self = shift;
	my $id = shift;
	my $c = delete $self->{id}{$id}
		or return warn "No such id: $id";
	return unless ref $c;
	my $jid = $c->{peer};
	
	delete $self->{jid}{ $jid->bare }{ $jid->res };
	if ( ! %{ $self->{jid}{ $jid->bare } } ) {
		delete $self->{jid}{ $jid->bare };
	}
}

sub gen_id {
	my $self = shift;
	my $size = shift // 10;
	state $chars = ['A'..'Z','a'..'z',0..9];
	my $id;
	do {{
		$id = join '', map { $chars->[rand($#$chars)] } 1..$size;
	}} while (exists $self->{id}{ $id });
	$self->{id}{$id}++;
	return $id;
}

sub gen_res {
	my $self = shift;
	my $jid = shift;
	my $size = shift // 5;
	state $chars = [ 'A'..'Z','a'..'z',0..9 ];
	unless ( exists $self->{jid}{ $jid } ) {
		$self->{jid}{ $jid } = {}
	}
	my $id;
	do {{
		$id = join '', map { $chars->[rand($#$chars)] } 1..$size;
	}} while ( exists $self->{jid}{$jid}{ $id } );
	$self->{jid}{$jid}{ $id }++;
	return $id;
}

sub check_res {
	my $self = shift;
	my $jid = shift;
	my $id = shift;
	return 0 unless exists $self->{jid}{ $jid };
	return exists ($self->{jid}{$jid}{ $id }) ? 1 : 0;
}

package AnyEvent::StreamXML::XMPP::Server;

use 5.008008;
use common::sense 2;m{
use strict;
use warnings;
};
use Carp;

use Event::Emitter;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Scalar::Util 'weaken';
use mro 'c3';


sub new {
	my $pk = shift;
	my $self = bless {@_}, $pk;
	$self->{cm} = AnyEvent::StreamXML::XMPP::Server::CM->new();
	$self->init();
	return $self;
}

sub init {
	my $self = shift;
	$self->{client_port} //= 5222;
	$self->{component_port} //= 5275;
	return;
}

sub start {
	weaken( my $self = shift );
	$self->{component_server} = tcp_server $self->{host}, $self->{component_port},sub {
		$_[0] or return warn;
		$self->component_accept(@_);
	}, sub { $self->{backlog} // 1024 };
	
	$self->{client_server} = tcp_server $self->{host}, $self->{client_port},sub {
		$_[0] or return warn;
		$self->client_accept(@_);
	}, sub { $self->{backlog} // 1024 };
	
	warn "Server started on $self->{host}; client=$self->{client_port}; component=$self->{component_port}\n";
	return;
}

sub component_accept {
	weaken(my $self = shift);
	my ($fh,$host,$port) = @_;
	#warn "accept component @_";
	my $id = $self->{cm}->gen_id();
	my $c = $self->{cnn}{"$host:$port"} = 
		AnyEvent::StreamXML::XMPP::Server::Conn::Component->new(
			id => $id,
			fh => $fh,
			debug_stream => $self->{debug_stream},
			setup => sub {
				my $c = shift;
				$self->{cm}->assign( $id, $c->{peer}, $c );
				$self->event("component" => $c);
			},
			end => sub {
				warn "Component end";
				$self->{cm}->free_id( $id );
			},
		);
	$self->{ids}{$id} = $c;
	return;
}

sub client_accept {
	weaken(my $self = shift);
	my ($fh,$host,$port) = @_;
	#warn "accept client @_";
	my $id = $self->{cm}->gen_id();
	my $c = $self->{cnn}{"$host:$port"} = 
		AnyEvent::StreamXML::XMPP::Server::Conn::Client->new(
			id => $id,
			fh => $fh,
			
			debug_stream => $self->{debug_stream},
			gen_res => sub {
				$self->{cm}->gen_res(@_);
			},
			check_res => sub {
				$self->{cm}->check_res(@_);
			},
			setup => sub {
				my $c = shift;
				$self->{cm}->assign( $id, $c->{full}, $c );
				
				$self->event("client" => $c);
				
				# client has established connection
				# handle iq/message/presence
				$c->on(
					presence => sub {
						my $c = shift;
						my $p = shift;
						if (!$p->from and !$p->to) {
							#warn "initial presence";
							$c->presence('', $c->{full}, $c->{full});
						} else {
							warn "presence -> ".$p->to;
						}
					},
				);
				
				return;
			},
			end => sub {
				warn "Client end";
				$self->{cm}->free_id( $id );
			},
		);
	$self->{ids}{$id} = $c;
	return;
}

1;

