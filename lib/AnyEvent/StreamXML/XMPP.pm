package AnyEvent::StreamXML::XMPP;

use parent 'AnyEvent::StreamXML';
use mro 'c3';
use common::sense;
use uni::perl ':dumper';
use XML::Hash::LX 0.0601;
use Carp;
use AnyEvent::StreamXML::XMPP::NS;

sub init {
	my $self = shift;
	$self->{seq} = 'aaaaa';
	$self->{jid} or croak "Need 'jid'";
	$self->{stream_ns} = ns('component_accept') unless defined $self->{stream_ns};
	$self->next::method();
}

sub nextid {
	my $self = shift;
	return 'ae-'.$self->{seq}++;
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
	$self->{sent_end}++ and return;
	$self->{h}->timeout(10);
	$self->send("</stream:stream>");
}

1;
