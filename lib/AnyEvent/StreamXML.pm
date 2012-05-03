package AnyEvent::StreamXML;

use 5.008008;
use common::sense 2;m{
use strict;
use warnings;
};
use Carp;

use Event::Emitter;
use parent 'AnyEvent::CNN::RW';
use AnyEvent::RW;

use AnyEvent::Socket;
use AnyEvent::Handle;

use XML::Fast::Stream;

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
=for rem
sub new {
	my $pk = shift;
	my $self = bless {@_}, $pk;
	#my $self = shift->SUPER::new(@_);
	$self->init();
	return $self;
}
=cut
sub init {
	my $self = shift;
	$self->{debug} //= 0;
	$self->{timeout}  ||= 3;
	$self->next::method(@_);
	$self->{send_color} = "33";
	$self->{recv_color} = "32";
	$self->{debug_stream} ||= 0;
	$self->{timers}     = {};
	$self->{_}          = {}; # some shit, like guards
	$self->{h}          = undef; # AE::Handle
	$self->{buffer_size} //= 8*1024,
	$self->on(__DIE__ => sub {
		my ($err, $e ) = @_;
		my ( $ev,$obj,@args ) = @{ $self->{__oe_exception_rec} };
		@args = () if $ev ne $e;
		warn "Unhandled exception on event $e: <$err> (@args)";
	});
	
	return;
}


sub _make_parser {
	weaken(my $self = shift);
	$self->{lxml} = XML::LibXML->new;
	
	$self->{stanza_handlers}{''} ||=  sub {
		$self->handles('stanza') or return warn "event `stanza' not handled\n$_[0]\n";
		$self->event(stanza => @_);
	};
	$self->{handlers}{StreamStart} ||= sub {
		$self->{stream_start_tag} = $_[1];
		$self->{stream_end_tag} = '</'.$_[0].'>';
		
		shift;
		$_[0] = $self->{lxml}->parse_string(
			$self->{stream_start_tag}.$self->{stream_end_tag}
		)->documentElement;
		
		$self->{h}->timeout(undef);
		$self->handles('stream_ready') or return warn "event `stream_ready' not handled\n";
		$self->event( stream_ready => @_ );
	};
	$self->{handlers}{Stanza}    ||= $self->{stanza_handlers};
	$self->{handlers}{StreamEnd} ||= sub {
		#warn "StreamEnd";
		$self->handles('stream_end') or return warn "event `stream_end' not handled\n";
		$self->event( stream_end => @_  )
	};
	$self->{parser} = XML::Fast::Stream->new({
		buffer => $self->{buffer_size},
		open   => $self->{handlers}{StreamStart},
		read   => sub {
			my $tag = shift;
			$_[0] = $self->{lxml}->parse_string(
				$self->{stream_start_tag}.$_[0].$self->{stream_end_tag}
			)->documentElement->firstChild;
			goto &{ 
				exists $self->{handlers}{Stanza}{$tag}
					?  $self->{handlers}{Stanza}{$tag}
					:  $self->{handlers}{Stanza}{''}
			};
		},
		close => $self->{handlers}{StreamEnd},
	});
	return;
}

sub _recv_data {
	my $self = shift;
	$self->{parser}->parse( ${ $_[0] } );
}

sub _on_connected_prepare {
	my ($self,$fh,$host,$port) = @_;
	#warn "success: @_";
	weaken $self;
	$self->_make_parser;
	$self->{h} = AnyEvent::RW->new(
		fh    => $self->{fh},
		debug => $self->{debug},
		timeout => $self->{timeout},
		read_size => $self->{buffer_size}, max_read_size => $self->{buffer_size},
		on_read => sub {
			$self or return;
			$self->debug_recv($_[0]);
			$self->_recv_data($_[0]);
		},
		on_end => sub {
			$self or return;
			warn "discon: @_";
			$self->disconnect(@_ ? @_ : "$!");
			$self->_reconnect_after;
		}
	);
	$self->send_start;
}

sub _on_connected_success {
	my ($self,$fh,$host,$port,$cb) = @_;
	$self->_on_connected_prepare($fh,$host,$port);
	$cb->($host,$port) if $cb;
	if ($self->handles('connected')) {
		$self->event( connected => ($host,$port) );
	}
	elsif (!$cb) {
		#warn "connected not handled!" ;
	}
}

sub disconnect {
	my $self = shift;
	#warn "Disconnect @_";
	$self->next::method(@_);
	$self->_cleanup;
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
