package AnyEvent::StreamXML::XMPP::JID;

use strict;
use Scalar::Util ();
use overload
	'""'     => sub { $_[0]->full },
	'bool'   => sub { 1 },
	'0+'     => sub { Scalar::Util::refaddr($_[0]) },
	fallback => 1;

sub import {
	no strict 'refs';
	my $pkg = shift;
	*{ caller().'::jid' } = sub ($) { $pkg->new($_[0]) };
}

sub new {
	my $pkg = shift;
	my $str = shift;
	my ($user,$dom,$res);
	if ((my $i = index($str, '@')) > -1 ) {
		$user = substr( $str, 0, $i, '');
		substr($str,0,1,'');
	}
	if ((my $i = index($str, '/')) > -1 ) {
		$res = substr( $str, $i+1, length($str) - $i, '');
		substr($str,-1,1,'');
	}
	$dom = $str;
	return bless [ $user,$dom, $res ];
}

sub bare {
	my $self = shift;
	return defined $self->[0] ? $self->[0].'@'.$self->[1] : $self->[1];
}

sub full {
	my $self = shift;
	return defined $self->[0] ? $self->[0].'@'.$self->[1].( defined $self->[2] ? '/' . $self->[2] : '' ) : $self->[1];
}

sub user { shift->[0] }
sub domain { shift->[1] }
sub res { shift->[2] } *resource = \&res;

1;
