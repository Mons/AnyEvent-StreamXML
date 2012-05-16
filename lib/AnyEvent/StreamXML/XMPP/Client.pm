	package AnyEvent::StreamXML::XMPP::Client;

	use uni::perl ':dumper';
	use parent 'AnyEvent::StreamXML::XMPP';
	use AnyEvent::StreamXML::XMPP::NS;
	use AnyEvent::StreamXML::XMPP::Iq;
	use AnyEvent::StreamXML::XMPP::Presence;
	use AnyEvent::StreamXML::XMPP::Message;
	use AnyEvent::StreamXML::XMPP::JID;
	use XML::Hash::LX;
	use MIME::Base64 qw(encode_base64 decode_base64);
	use Scalar::Util 'weaken';

	
	sub auth_plain {
		my $self = shift;
		my $cbx = pop;
		my $cb = sub {
			delete $self->{stanza_handlers}{success};
			delete $self->{stanza_handlers}{failure};
			$cbx->(@_);
		};
		$self->{stanza_handlers}{success} = sub {
			my $s = shift;
			$cb->($s);
		};
		$self->{stanza_handlers}{failure} = sub {
			my $s = shift;
			$cb->(undef,$s);
		};
		my $login_pass = "\0".($self->{login} // $self->{jid}->user)."\0".$self->{password};
		#<auth xmlns="urn:ietf:params:xml:ns:xmpp-sasl" mechanism="PLAIN">XXXXXXXXXXXXXXXXXXXXXXXXXXXX</auth>
		$self->send({
			auth => {
				-xmlns => ns('sasl'),
				-mechanism => "PLAIN",
				'#text' => encode_base64($login_pass),
			},
		});
	}
	
	sub init {
		my $self = shift;
		$self->{stream_ns} = ns('client') unless defined $self->{stream_ns};
		$self->next::method();
		$self->{seq_pref} ||= 'cl';
		$self->{jid} or croak "Need 'jid'";
		ref $self->{jid} or $self->{jid} = AnyEvent::StreamXML::XMPP::JID->new($self->{jid});
		$self->{resource} //= $self->{jid}->res || 'ae-sxml-xmpp'; $self->{jid}->res(undef);
		$self->{handlers}{StreamStart} = sub {
			#warn dumper \@_;
			$self->{stream} = xml2hash(shift)->{'stream:stream'};
			#warn "stream_start ".dumper $self->{stream};
		};
		$self->{stanza_handlers}{'stream:error'} = sub {
			my $s = shift;
			$self->disconnect(eval{ $s->firstChild->nodeName } // "$s");
		};
		$self->{stanza_handlers}{'stream:features'} = sub {
			my $s = shift;
			$self->{features} = {};
			#warn dumper xml2hash($s)->{'stream:features'};

			my $x;
			if (($x) = $s->getElementsByTagName('bind')) {
				$self->{features}{bind} = $x->getAttribute('xmlns');
			}
			if (($x) = $s->getElementsByTagName('session')) {
				$self->{features}{session} = $x->getAttribute('xmlns');
			}
			if (($x) = $s->getElementsByTagName('starttls')) {
				$self->{features}{starttls} = $x->getAttribute('xmlns');
			}
			if (($x) = $s->getElementsByTagName('mechanisms')) {
				for my $mech ( $x->getElementsByTagName('mechanism') ) {
					$self->{features}{mechanisms}{$mech->textContent}++;
				}
			}
			
			
			if ($self->{use_ssl} and $self->{features}{starttls} and !$self->{ssl}) {
				$self->{want_ssl_proceed} = 1;
				$self->send('<starttls xmlns="urn:ietf:params:xml:ns:xmpp-tls"/>');
				return;
			}
			
			if ($self->{features}{mechanisms}) {
				# Auth.
				$self->auth_plain(sub {
					#warn "auth: @_";
					if (shift) {
						weaken(my $c = $self);
						$self->_make_parser;
						$self->send_start;
						return;
					} else {
						warn "Auth failure, disconnect";
						$self->event("failure" => @_);
						$self->disconnect("Auth failure");
					}
				});
				return;
			}
			$self->{h}->timeout(0);
			my @next;@next = (
				sub {
					#warn "bind $self->{jid} / $self->{resource}";
					$self->request({
						iq => {
							-type => 'set',
							bind => {
								-xmlns => ns('bind'),
								resource => $self->{resource},
							}
						}
					}, sub {
						if (my $iq = shift) {
							my ($jid) = $iq->getElementsByTagName('jid');
							if ($jid) {
								$self->{jid} = AnyEvent::StreamXML::XMPP::JID->new($jid->textContent);
								(shift @next)->();
							} else {
								$self->disconnect("Can't find jid in response");
							}
						} else {
							$self->disconnect("Bind failed: @_");
						}
					});
				},
				sub {
					$self->request({
						iq => {
							-type => 'set',
							session => {
								-xmlns => ns('session'),
							}
						}
					}, sub {
						(shift @next)->();
					});
				},
				sub {
					if ($self->{use_ping}) {
						$self->{timers}{wping} = AE::timer 15,15,sub {
							$self->send(' ');
						};
					}
					$self->request({
						iq => {
							query => {
								-xmlns => ns('roster'),
							}
						}
					}, sub {
						$self->{roster} = shift;
						(shift @next)->();
					});
				},
				sub {
					$self->send('<presence/>');
					$self->event(ready => (delete $self->{roster}));
				}
			);
			(shift @next)->();
=for rem
my $c = $self;
						$c->request({
							iq => {
								-to => $self->{stream}{-from}, # Ask our server about disco
								query => { -xmlns => ns( 'ping' ) },
								#query => { -xmlns => ns( 'disco_info' ) },
							}
						},sub {
							#warn "ping reply: in ".sprintf("%0.4fs", time - $at);
						});
return;
#=cut

=cut
				
		};
		$self->{stanza_handlers}{proceed} = sub {
			my $s = shift;
			if ($s->getAttribute('xmlns') eq ns('tls')) {
				if($self->{want_ssl_proceed}) {
					$self->{h}->starttls('connect');
					$self->{ssl} = 1;
					$self->_make_parser;
					$self->send_start;
				}
			}
		};
		return;
	}
	sub send_start {
		my $self = shift;
		my $s = hash2xml( {
			'stream:stream' => {
				'-version'      => "1.0",
				'-xml:lang'     => "en",
				
				'-xmlns'        => $self->{stream_ns},
				'-xmlns:stream' => ns('etherx_streams'),
				'-from'         => $self->{jid},
				'-to'           => $self->{jid}->domain,
			}
		}, doc => 1 )->documentElement->toString;
		$s =~ s{/>$}{>};
		$self->send($s);
	}

1;

