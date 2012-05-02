package AnyEvent::StreamXML;

use 5.008008;
use common::sense 2;m{
use strict;
use warnings;
};
use Carp;

use Event::Emitter;
use AnyEvent::Socket;
use AnyEvent::Handle;

#use XML::Fast::Stream;

use XML::Parser;
use XML::Parser::Style::XMPP;
use Try::Tiny;

use Scalar::Util 'weaken';
use mro 'c3';

=head1 ATTRS

=over 4

=item reconnect => 0 | timeout
=item 

=back

=cut

sub debug_recv {
	my $self = shift;
	$self->{debug_stream} or return;
	my $rbuf = shift;
	my $buf = $$rbuf;
	substr($buf, -1) = '' while substr($buf, -1) eq "\n";
	use POSIX 'strftime';
	my $time = strftime( '%b %d %H:%M:%S', localtime() );
	utf8::encode($buf) if utf8::is_utf8($buf);
	binmode STDOUT, ':raw';
	print STDOUT "\e[0;37m$time in \e[1;$self->{recv_color}m>>\t\e[0;$self->{recv_color}m$buf\e[0m\n";

}

sub debug_send {
	my $self = shift;
	$self->{debug_stream} or return;
	my $rbuf = shift;
	use POSIX 'strftime';
	my $time = strftime( '%b %d %H:%M:%S', localtime() );
	binmode STDOUT, ':raw';
	print STDOUT "\e[0;37m$time ou \e[1;$self->{send_color}m<<\t\e[0;$self->{send_color}m$$rbuf\e[0m\n";
}

sub ref2xml : method {
	my $self = shift;
	try { require XML::Hash::LX; }
	catch { croak "Can't load XML::Hash::LX for hash 2 xml conversion. Either install it or redefine `hash2xml' method ($_)" };
	XML::Hash::LX::hash2xml($_[0], 'doc' => 1)->documentElement;
}

sub _compose {
	my $self = shift;
	my ($s,%args);
	if (@_ > 1 and !ref $_[0]) {
		$s = { @_ };
	}
	elsif ( @_ ==1 and ref $_[0] ) {
		$s = shift;
	}
	else {
		$s = shift;
		%args = @_;
	}
	if (UNIVERSAL::isa( $s, 'HASH' )) {
		use uni::perl ':dumper';
		#warn "compose from hash ".dumper $s;
		$s = $self->ref2xml($s);
	} else {
		$s = $s;
	}
	#warn "composed: '$s'";
	return $s;
}

sub send {
	my $self = shift;
	$self->{h} or return Carp::cluck "Can't send() without handle at @{[ (caller)[1,2] ]}\n";
	my $s = $self->_compose(@_);
	$self->{debug_send_stanza} and $self->{debug_send_stanza}->($s);
	#eval {
	#	if ($s->nodeName eq 'iq' and $s->getAttribute('type') ne 'result') {
	#		warn "$s";
	#	}
	#};
	my $buf = "$s";
	$self->debug_send(\$buf);
	utf8::encode $buf if utf8::is_utf8($buf);
	$self->{h}->push_write( $buf."\n" );
	return;
}

sub new {
	my $pk = shift;
	my $self = bless {@_}, $pk;
	#my $self = shift->SUPER::new(@_);
	$self->init();
	return $self;
}

sub init {
	my $self = shift;
	$self->{send_color} = "33";
	$self->{recv_color} = "32";
	$self->{debug}        ||= 0;
	$self->{debug_stream} ||= 0;
	$self->{connected}  = 0;
	$self->{connecting} = 0;
	$self->{reconnect}  = 1 unless defined $self->{reconnect};
	$self->{timeout}  ||= 3;
	$self->{timers}     = {};
	$self->{_}          = {}; # some shit, like guards
	$self->{h}          = undef; # AE::Handle
	$self->on(__DIE__ => sub {
		my ($err, $e ) = @_;
		my ( $ev,$obj,@args ) = @{ $self->{__oe_exception_rec} };
		@args = () if $ev ne $e;
		warn "Unhandled exception on event $e: <$err> (@args)";
=for rem
		my $type;
		if (
			UNIVERSAL::isa( $args[0], 'Virtus::Reg::Stanza::Iq' )
			or (
				UNIVERSAL::isa( $args[0], 'XML::LibXML::Node' )
				and $args[0]->nodeName eq 'iq'
				and $type = $args[0]->getAttribute('type')
				and ( $type eq 'get' or $type eq 'set' )
			)
		) {
			warn "Unhandled exception during iq processing ($e) <$err>. Send 500";
			$self->error($args[0],'internal-server-error');
		} else {
			warn "Unhandled exception on event $e: <$err>";
		}
=cut
	});
	
	return;
}


sub connect {
	my $self = shift;
	$self->{connecting} and return;
	$self->{connecting} = 1;
	weaken $self;
	warn "Connecting to $self->{host}:$self->{port}..." if $self->{debug};
	$self->{_}{con}{cb} = sub {
		pop;
		delete $self->{_}{con};
		if (my $fh = shift) {
			$self->{connecting} = 0;
			$self->{connected} = 1;
			$self->_connected($fh,@_);
		} else {
			$self->event(connfail => "$!");
			$self->_reconnect_after(); # watches for connected/connecting
		}
	};
	$self->{_}{con}{pre} = sub { $self->{timeout} };
	$self->{_}{con}{grd} =
		AnyEvent::Socket::tcp_connect
			$self->{host}, $self->{port},
			$self->{_}{con}{cb}, $self->{_}{con}{pre}
	;
	return;
}

sub _make_parser {
	weaken(my $self = shift);
	$self->{stanza_handlers}{''} ||=  sub {
		warn "Stanza";
		$self->handles('stanza') or return warn "event `stanza' not handled\n$_[0]\n";
		$self->event(stanza => @_);
	};
	$self->{handlers}{StreamStart} ||= sub {
		$self->{h}->timeout(undef);
		$self->handles('stream_ready') or return warn "event `stream_ready' not handled\n";
		$self->event( stream_ready => @_ );
	};
	$self->{handlers}{Stanza} ||= $self->{stanza_handlers};
	$self->{handlers}{StreamEnd} ||= sub {
		#warn "StreamEnd";
		$self->handles('stream_end') or return warn "event `stream_end' not handled\n";
		$self->event( stream_end => @_  )
	};
	my $parser = XML::Parser->new(
		Style => 'XMPP',
		On => $self->{handlers},
	);
	my $sax = $parser->parse_start();
	$self->{parser} = $sax;
}

sub _connected {
	my ($self,$fh,$host,$port) = @_;
	# Create handle, parser, etc...
	weaken($self);
	$self or return warn("self immediately destroyed?");
	
	$self->_make_parser();
	delete $self->{sent_end};
	
	$self->{cb}{eof} = sub {
		$self or return;
		warn "Eof on handle" if $self->{debug};
		try { $self->{h}->destroy; }
		catch { warn $_ };
		delete $self->{h};
		$self->disconnect();
		$self->_reconnect_after();
	};
	
	$self->{cb}{err} = sub {
		$self or return;
		my $e = "$!";
		warn "Error $e on handle" if $self->{debug};
		try { $self->{h}->destroy; }
		catch { warn $_ };
		delete $self->{h};
		if (!$self->{destroying} and $self->{sent_end} and $!{ETIMEDOUT}) {
			#$self->_reconnect_after(); # watches for connected/connecting
			$self->disconnect();
			$self->_reconnect_after();
			return;
		}
		if ($self->{destroying}) {
			$e = "Connection closed";
		}
		warn "Error on handle: $e";# if $self->{debug};
		$self->disconnect("Error: $e");
		$self->_reconnect_after(); # watches for connected/connecting
	};
	
	$self->{cb}{read} = sub {
		$self and $self->{parser} or return;
		my $h = shift;
		$self->debug_recv(\$h->{rbuf});
		try {
			$self->{parser}->parse_more( substr($h->{rbuf},0,length($h->{rbuf}),'') );
		}
		catch {
			warn "Parse died <$_>.";
			$self->disconnect("Error: $_");
			$self->_reconnect_after(); # watches for connected/connecting
		};
	};
	
	$self->{h} = AnyEvent::Handle->new(
		fh => $fh,
		autocork  => 1,
		keepalive => 1,
		#timeout   => 10,
		on_eof    => $self->{cb}{eof},
		on_error  => $self->{cb}{err},
		on_read   => $self->{cb}{read},
	);
	
	warn "Connected to $host:$port ($self->{h})\n" if $self->{debug};
	
	$self->{h}->timeout(10);
	$self->send_start;
	$self->event( connected => () );
}

sub _disconnected {
	my $self = shift;
	# Destroy handle, parser, etc...
	if ($self->{h}) {{
		try { $self->{h}->destroy; };
		catch { warn $_ }
		delete $self->{h};
	}}
	warn "Disconnected\n" if $self->{debug};# or $self->{debug_stream};
	$self->_cleanup;
	return;
}

sub _cleanup {
	my $self = shift;
	delete $self->{timers};
	delete $self->{parser};
	my $cl = delete $self->{clean};
	for (@$cl) { $_->(); }
	return;
}

sub cleanup {
	my $self = shift;
	push @{ $self->{clean} ||= [] }, @_;
	return;
}

sub _reconnect_after {
	weaken( my $self = shift );
	$self->{reconnect} or return $self->{connecting} = 0;
	$self->{timers}{reconnect} = AE::timer $self->{reconnect},0,sub {
		$self or return;
		delete $self->{timers}{reconnect};
		$self->{connecting} = 0;
		$self->connect;
	};
	return;
}

sub reconnect {
	my $self = shift;
	$self->disconnect(@_);
	$self->connect;
}

sub disconnect {
	my $self = shift;
	my $wascon = $self->{connected} || $self->{connecting};
	$self->send_end if $self->{connected};
	$self->_disconnected;
	$self->{connected}  = $self->{connecting} =  0;
	delete $self->{timers}{reconnect};
	$self->event('disconnect',@_) if $wascon;
	return;
}

sub AnyEvent::StreamXML::destroyed::AUTOLOAD {}

sub destroy {
	my ($self) = @_;
	$self->DESTROY;
	bless $self, "AnyEvent::StreamXML::destroyed";
}

sub DESTROY {
	my $self = shift;
	warn "(".int($self).") Destroying AE::StreamXML" if $self->{debug};
	local $@;
	local $SIG{__DIE__} = sub { warn "Exception during StreamXML.DESTROY: @_"; };
	$self->disconnect;
	%$self = ();
}

sub send_start {
	my $self = shift;
	# Send something at the beginning
}

sub send_end {
	my $self = shift;
	# Send something at the end
	$self->{sent_end}++ and return;
	$self->disconnect;
}

=head1 NAME

AnyEvent::StreamXML - ...

=cut

our $VERSION = '0.01'; $VERSION = eval($VERSION);

=head1 SYNOPSIS

    package Sample;
    use AnyEvent::StreamXML;

    ...

=head1 DESCRIPTION

    ...

=cut


=head1 METHODS

=over 4

=item ...()

...

=back

=cut

=head1 AUTHOR

Mons Anderson, C<< <mons@cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 Mons Anderson, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

=cut

1;
