package AnyEvent::StreamXML::XMPP::Presence;

use uni::perl;
use parent 'AnyEvent::StreamXML::XMPP::Stanza';

sub type { $_[0][2]{type} ||= $_[0][0]->getAttribute('type') || 'available'; }

1;
