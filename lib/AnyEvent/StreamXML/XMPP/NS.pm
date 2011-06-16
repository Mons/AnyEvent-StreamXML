package AnyEvent::StreamXML::XMPP::NS;

use common::sense;
use Carp;

sub import {
	my $me = shift;
	my $caller = caller;
	no strict 'refs';
	for (@_ ? @_ : qw(ns rns)) {
		croak "`$_' not exported by $me" unless defined &$_;
		*{$caller . '::' . $_} = \&$_;
	}
}

our %NS = (
        activity             => 'http://jabber.org/protocol/activity',
        address              => 'http://jabber.org/protocol/address',
        amp                  => 'http://jabber.org/protocol/amp',
        amp_errors           => 'http://jabber.org/protocol/amp#errors',
        bytestreams          => 'http://jabber.org/protocol/bytestreams',
        caps                 => 'http://jabber.org/protocol/caps',
        chatstates           => 'http://jabber.org/protocol/chatstates',
        commands             => 'http://jabber.org/protocol/commands',
        compress             => 'http://jabber.org/protocol/compress',
        disco_info           => 'http://jabber.org/protocol/disco#info',
        disco_items          => 'http://jabber.org/protocol/disco#items',
        feature_neg          => 'http://jabber.org/protocol/feature-neg',
        geoloc               => 'http://jabber.org/protocol/geoloc',
        http_auth            => 'http://jabber.org/protocol/http-auth',
        httpbind             => 'http://jabber.org/protocol/httpbind',
        ibb                  => 'http://jabber.org/protocol/ibb',
        mood                 => 'http://jabber.org/protocol/mood',
        muc                  => 'http://jabber.org/protocol/muc',
        muc_admin            => 'http://jabber.org/protocol/muc#admin',
        muc_owner            => 'http://jabber.org/protocol/muc#owner',
        muc_user             => 'http://jabber.org/protocol/muc#user',
        nick                 => 'http://jabber.org/protocol/nick',
        offline              => 'http://jabber.org/protocol/offline',
        physloc              => 'http://jabber.org/protocol/physloc',
        pubsub               => 'http://jabber.org/protocol/pubsub',
        pubsub_errors        => 'http://jabber.org/protocol/pubsub#errors',
        pubsub_event         => 'http://jabber.org/protocol/pubsub#event',
        pubsub_owner         => 'http://jabber.org/protocol/pubsub#owner',
        rc                   => 'http://jabber.org/protocol/rc',
        rosterx              => 'http://jabber.org/protocol/rosterx',
        sipub                => 'http://jabber.org/protocol/sipub',
        soap                 => 'http://jabber.org/protocol/soap',
        soap_fault           => 'http://jabber.org/protocol/soap#fault',
        waitinglist          => 'http://jabber.org/protocol/waitinglist',
        xhtml_im             => 'http://jabber.org/protocol/xhtml-im',
        xdata_layout         => 'http://jabber.org/protocol/xdata-layout',
        xdata_validate       => 'http://jabber.org/protocol/xdata-validate',
        client               => 'jabber:client',
        component_accept     => 'jabber:component:accept',
        component_connect    => 'jabber:component:connect',
        auth                 => 'jabber:iq:auth',
        gateway              => 'jabber:iq:gateway',
        last                 => 'jabber:iq:last',
        oob                  => 'jabber:iq:oob',
        privacy              => 'jabber:iq:privacy',
        private              => 'jabber:iq:private',
        register             => 'jabber:iq:register',
        roster               => 'jabber:iq:roster',
        rpc                  => 'jabber:iq:rpc',
        search               => 'jabber:iq:search',
        version              => 'jabber:iq:version',
        server               => 'jabber:server',
        x_conference         => 'jabber:x:conference',
        x_data               => 'jabber:x:data',
        x_encrypted          => 'jabber:x:encrypted',
        x_oob                => 'jabber:x:oob',
        x_signed             => 'jabber:x:signed',
        roster_delimiter     => 'roster:delimiter',
        bind                 => 'urn:ietf:params:xml:ns:xmpp-bind',
        e2e                  => 'urn:ietf:params:xml:ns:xmpp-e2e',
        sasl                 => 'urn:ietf:params:xml:ns:xmpp-sasl',
        session              => 'urn:ietf:params:xml:ns:xmpp-session',
        stanzas              => 'urn:ietf:params:xml:ns:xmpp-stanzas',
        streams              => 'urn:ietf:params:xml:ns:xmpp-streams',
        tls                  => 'urn:ietf:params:xml:ns:xmpp-tls',
        archive              => 'urn:xmpp:archive',
        attention_0          => 'urn:xmpp:attention:0',
        avatar_data          => 'urn:xmpp:avatar:data',
        avatar_metadata      => 'urn:xmpp:avatar:metadata',
        bob                  => 'urn:xmpp:bob',
        captcha              => 'urn:xmpp:captcha',
        delay                => 'urn:xmpp:delay',
        errors               => 'urn:xmpp:errors',
        langtrans            => 'urn:xmpp:langtrans',
        langtrans_items      => 'urn:xmpp:langtrans#items',
        media_element        => 'urn:xmpp:media-element',
        pie                  => 'urn:xmpp:pie',
        ping                 => 'urn:xmpp:ping',
        receipts             => 'urn:xmpp:receipts',
        sm_2                 => 'urn:xmpp:sm:2',
        ssn                  => 'urn:xmpp:ssn',
        time                 => 'urn:xmpp:time',
        xbosh                => 'urn:xmpp:xbosh',
        vcard_temp           => 'vcard-temp',
        vcard_temp_x_update  => 'vcard-temp:x:update',
        stats                => 'http://jabber.org/protocol/stats',
        
        etherx_streams       => 'http://etherx.jabber.org/streams',
);
my %RNS = reverse %NS;

our %NS;

sub register {
	my $ns = shift;
	my $alias = shift || do {
		local $_ = $ns;
		s{^urn:xmpp:}{};
		s{^jabber:(?:iq:|)}{};
		s{^urn:ietf:params:xml:ns:(?:xmpp-|)}{};
		s{^http://jabber\.org/protocol/}{};
		tr{#:-}{___};
		$_;
	};
	croak "Alias $alias already registered as `$NS{ $alias }'. Can't register `$ns'" if exists $NS{ $alias } and $NS{ $alias } ne $ns;
	croak "Namespace `$ns' already registered `$RNS{ $ns }'. Can't register `$ns' as `$alias'" if exists $RNS{ $ns } and $RNS{ $alias } ne $alias;
	$NS{ $alias } = $ns;
	$RNS{ $ns } = $alias;
	return;
}

sub ns($) {
	exists $NS{ $_[0] } ? $NS{$_[0]} : $_[0];
}

sub rns($) {
	exists $RNS{ $_[0] } ? $RNS{$_[0]} : $_[0];
}

1;
