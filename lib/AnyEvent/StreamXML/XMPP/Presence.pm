package AnyEvent::StreamXML::XMPP::Presence;

use uni::perl;
use parent 'AnyEvent::StreamXML::XMPP::Stanza';

sub type { shift->attr('type', @_) || 'available' }

1;
